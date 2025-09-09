#include "DisassemblyEngine.hpp"
#include <algorithm>
#include <chrono>
#include <thread>
#include <cstring>
#include <immintrin.h>  // For SIMD optimization

namespace MacDBG {

// Instruction type bit flags
enum InstructionType : uint8_t {
    TYPE_NONE = 0,
    TYPE_JUMP = 1,
    TYPE_CONDITIONAL = 2,
    TYPE_CALL = 4,
    TYPE_RET = 8,
    TYPE_BRANCH = 16
};

// Jump instruction lookup table (compile-time optimized)
struct JumpInfo {
    const char* mnemonic;
    uint8_t type;
    uint8_t length;
};

static constexpr JumpInfo JUMP_TABLE[] = {
    {"jmp", TYPE_JUMP, 3},
    {"je", TYPE_JUMP | TYPE_CONDITIONAL, 2},
    {"jne", TYPE_JUMP | TYPE_CONDITIONAL, 3},
    {"jz", TYPE_JUMP | TYPE_CONDITIONAL, 2},
    {"jnz", TYPE_JUMP | TYPE_CONDITIONAL, 3},
    {"jl", TYPE_JUMP | TYPE_CONDITIONAL, 2},
    {"jle", TYPE_JUMP | TYPE_CONDITIONAL, 3},
    {"jg", TYPE_JUMP | TYPE_CONDITIONAL, 2},
    {"jge", TYPE_JUMP | TYPE_CONDITIONAL, 3},
    {"ja", TYPE_JUMP | TYPE_CONDITIONAL, 2},
    {"jae", TYPE_JUMP | TYPE_CONDITIONAL, 3},
    {"jb", TYPE_JUMP | TYPE_CONDITIONAL, 2},
    {"jbe", TYPE_JUMP | TYPE_CONDITIONAL, 3},
    {"jo", TYPE_JUMP | TYPE_CONDITIONAL, 2},
    {"jno", TYPE_JUMP | TYPE_CONDITIONAL, 3},
    {"js", TYPE_JUMP | TYPE_CONDITIONAL, 2},
    {"jns", TYPE_JUMP | TYPE_CONDITIONAL, 3},
    {"jc", TYPE_JUMP | TYPE_CONDITIONAL, 2},
    {"jnc", TYPE_JUMP | TYPE_CONDITIONAL, 3},
    {"call", TYPE_CALL, 4},
    {"ret", TYPE_RET, 3},
    {"retq", TYPE_RET, 4},
};

DisassemblyEngine::DisassemblyEngine() {
    instructions_.reserve(10000);  // Pre-allocate for performance
    jumpTargets_.reserve(1000);
    addressCache_.reserve(10000);
}

DisassemblyEngine::~DisassemblyEngine() = default;

void DisassemblyEngine::setInstructions(const std::vector<Instruction>& instructions) {
    std::unique_lock lock(rwLock_);
    
    instructions_ = instructions;
    
    // Sort by address for binary search
    std::sort(instructions_.begin(), instructions_.end(), 
              [](const Instruction& a, const Instruction& b) {
                  return a.address < b.address;
              });
    
    updateAddressRange();
    rebuildAddressCache();
    jumpsDirty_.store(true);
    
    stats_.instructionCount = instructions_.size();
}

void DisassemblyEngine::appendInstructions(const std::vector<Instruction>& newInstructions) {
    std::unique_lock lock(rwLock_);
    
    size_t oldSize = instructions_.size();
    instructions_.insert(instructions_.end(), newInstructions.begin(), newInstructions.end());
    
    // Re-sort if necessary (should be rare with proper LLDB ordering)
    bool needsSort = false;
    for (size_t i = oldSize; i < instructions_.size(); ++i) {
        if (i > 0 && instructions_[i].address < instructions_[i-1].address) {
            needsSort = true;
            break;
        }
    }
    
    if (needsSort) {
        std::sort(instructions_.begin(), instructions_.end(),
                  [](const Instruction& a, const Instruction& b) {
                      return a.address < b.address;
                  });
    }
    
    updateAddressRange();
    rebuildAddressCache();
    jumpsDirty_.store(true);
    
    stats_.instructionCount = instructions_.size();
}

const Instruction* DisassemblyEngine::findByAddress(uint64_t address) const {
    auto start = std::chrono::high_resolution_clock::now();
    
    std::shared_lock lock(rwLock_);
    
    // Try cache first
    auto cacheIt = addressCache_.find(address);
    if (cacheIt != addressCache_.end()) {
        auto end = std::chrono::high_resolution_clock::now();
        stats_.lastLookupTimeNs = std::chrono::duration_cast<std::chrono::nanoseconds>(end - start).count();
        return &instructions_[cacheIt->second];
    }
    
    // Binary search fallback
    size_t index = binarySearchAddress(address);
    if (index < instructions_.size() && instructions_[index].address == address) {
        // Update cache
        addressCache_[address] = index;
        auto end = std::chrono::high_resolution_clock::now();
        stats_.lastLookupTimeNs = std::chrono::duration_cast<std::chrono::nanoseconds>(end - start).count();
        return &instructions_[index];
    }
    
    auto end = std::chrono::high_resolution_clock::now();
    stats_.lastLookupTimeNs = std::chrono::duration_cast<std::chrono::nanoseconds>(end - start).count();
    return nullptr;
}

size_t DisassemblyEngine::findIndexByAddress(uint64_t address) const {
    std::shared_lock lock(rwLock_);
    
    auto cacheIt = addressCache_.find(address);
    if (cacheIt != addressCache_.end()) {
        return cacheIt->second;
    }
    
    return binarySearchAddress(address);
}

std::vector<const Instruction*> DisassemblyEngine::getVisibleRange(size_t startIndex, size_t count) const {
    std::shared_lock lock(rwLock_);
    
    std::vector<const Instruction*> result;
    result.reserve(count);
    
    size_t endIndex = std::min(startIndex + count, instructions_.size());
    for (size_t i = startIndex; i < endIndex; ++i) {
        result.push_back(&instructions_[i]);
    }
    
    return result;
}

void DisassemblyEngine::analyzeJumps() {
    if (!jumpsDirty_.load()) return;
    
    auto start = std::chrono::high_resolution_clock::now();
    
    // Launch analysis on background thread to avoid blocking UI
    std::thread([this, start]() {
        analyzeJumpsInternal();
        
        auto end = std::chrono::high_resolution_clock::now();
        stats_.analysisTimeUs = std::chrono::duration_cast<std::chrono::microseconds>(end - start).count();
        jumpsDirty_.store(false);
    }).detach();
}

void DisassemblyEngine::updateAddressRange() {
    if (instructions_.empty()) {
        minAddress_.store(0);
        maxAddress_.store(0);
        return;
    }
    
    minAddress_.store(instructions_.front().address);
    maxAddress_.store(instructions_.back().address);
}

void DisassemblyEngine::rebuildAddressCache() {
    addressCache_.clear();
    for (size_t i = 0; i < instructions_.size(); ++i) {
        addressCache_[instructions_[i].address] = i;
    }
}

size_t DisassemblyEngine::binarySearchAddress(uint64_t address) const {
    return std::lower_bound(instructions_.begin(), instructions_.end(), address,
                           [](const Instruction& inst, uint64_t addr) {
                               return inst.address < addr;
                           }) - instructions_.begin();
}

void DisassemblyEngine::analyzeJumpsInternal() {
    std::unique_lock lock(rwLock_);
    
    jumpTargets_.clear();
    jumpTargets_.reserve(instructions_.size() / 10);  // Estimate ~10% jumps
    
    for (size_t i = 0; i < instructions_.size(); ++i) {
        Instruction& inst = instructions_[i];
        
        // Reset jump info
        inst.jumpTargetIndex = UINT32_MAX;
        inst.instructionType = parseInstructionType(inst.mnemonic);
        
        // Parse jump target if this is a jump instruction
        if (inst.instructionType & (TYPE_JUMP | TYPE_CALL)) {
            uint64_t targetAddr = parseJumpTarget(inst.operands);
            if (targetAddr != 0) {
                // Find target instruction index
                size_t targetIndex = binarySearchAddress(targetAddr);
                
                JumpTarget jumpTarget;
                jumpTarget.targetAddress = targetAddr;
                jumpTarget.targetIndex = (targetIndex < instructions_.size() && 
                                        instructions_[targetIndex].address == targetAddr) 
                                       ? static_cast<uint32_t>(targetIndex) : UINT32_MAX;
                jumpTarget.jumpType = inst.instructionType;
                
                inst.jumpTargetIndex = static_cast<uint32_t>(jumpTargets_.size());
                jumpTargets_.push_back(jumpTarget);
            }
        }
    }
    
    stats_.jumpCount = jumpTargets_.size();
}

uint8_t DisassemblyEngine::parseInstructionType(const char* mnemonic) const {
    // Fast lookup using compile-time table
    for (const auto& jump : JUMP_TABLE) {
        if (strncmp(mnemonic, jump.mnemonic, jump.length) == 0) {
            return jump.type;
        }
    }
    return TYPE_NONE;
}

uint64_t DisassemblyEngine::parseJumpTarget(const char* operands) const {
    // Fast hex parsing - optimized for common cases
    const char* ptr = operands;
    
    // Skip whitespace
    while (*ptr == ' ' || *ptr == '\t') ptr++;
    
    // Look for 0x prefix
    if (ptr[0] == '0' && (ptr[1] == 'x' || ptr[1] == 'X')) {
        ptr += 2;
        uint64_t result = 0;
        
        // Fast hex conversion
        while (*ptr) {
            char c = *ptr;
            if (c >= '0' && c <= '9') {
                result = (result << 4) | (c - '0');
            } else if (c >= 'a' && c <= 'f') {
                result = (result << 4) | (c - 'a' + 10);
            } else if (c >= 'A' && c <= 'F') {
                result = (result << 4) | (c - 'A' + 10);
            } else {
                break;
            }
            ptr++;
        }
        
        return result;
    }
    
    return 0;
}

DisassemblyEngine::Stats DisassemblyEngine::getStats() const {
    return stats_;
}

} // namespace MacDBG
