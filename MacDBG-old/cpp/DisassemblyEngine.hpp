#pragma once
#include <vector>
#include <unordered_map>
#include <memory>
#include <string>
#include <mutex>
#include <atomic>

namespace MacDBG {

// Fast, cache-friendly instruction representation
struct Instruction {
    uint64_t address;
    uint32_t size;
    uint32_t jumpTargetIndex;  // Index into jumpTargets array, UINT32_MAX if no jump
    char bytes[16];           // Raw bytes (most instructions ≤ 16 bytes)
    char mnemonic[12];        // Instruction name (most ≤ 12 chars)
    char operands[64];        // Operands string (most ≤ 64 chars)
    uint8_t instructionType;  // Bitflags: JUMP=1, CONDITIONAL=2, CALL=4, etc.
    uint8_t bytesLength;      // Actual byte count
    uint8_t padding[2];       // Align to 128 bytes for cache efficiency
} __attribute__((packed));

static_assert(sizeof(Instruction) <= 128, "Instruction must fit in cache line");

// Jump target information
struct JumpTarget {
    uint64_t targetAddress;
    uint32_t targetIndex;     // Index in instructions array, UINT32_MAX if off-screen
    uint8_t jumpType;         // CONDITIONAL, UNCONDITIONAL, CALL, etc.
};

class DisassemblyEngine {
public:
    DisassemblyEngine();
    ~DisassemblyEngine();

    // Core operations (thread-safe)
    void setInstructions(const std::vector<Instruction>& instructions);
    void appendInstructions(const std::vector<Instruction>& instructions);
    
    // Fast lookups (O(log n) or O(1))
    const Instruction* findByAddress(uint64_t address) const;
    size_t findIndexByAddress(uint64_t address) const;
    
    // Range queries for UI (extremely fast)
    std::vector<const Instruction*> getVisibleRange(size_t startIndex, size_t count) const;
    
    // Jump analysis (parallel, cached)
    void analyzeJumps();
    const std::vector<JumpTarget>& getJumpTargets() const { return jumpTargets_; }
    
    // State queries
    size_t getInstructionCount() const { return instructions_.size(); }
    uint64_t getMinAddress() const { return minAddress_.load(); }
    uint64_t getMaxAddress() const { return maxAddress_.load(); }
    
    // Performance stats
    struct Stats {
        uint64_t instructionCount;
        uint64_t jumpCount;
        uint64_t analysisTimeUs;
        uint64_t lastLookupTimeNs;
    };
    Stats getStats() const;

private:
    // Main instruction storage (sorted by address)
    std::vector<Instruction> instructions_;
    
    // Jump analysis results
    std::vector<JumpTarget> jumpTargets_;
    
    // Fast address lookup (binary search optimized)
    mutable std::unordered_map<uint64_t, size_t> addressCache_;
    
    // Atomic state for lock-free reads
    std::atomic<uint64_t> minAddress_{0};
    std::atomic<uint64_t> maxAddress_{0};
    std::atomic<bool> jumpsDirty_{true};
    
    // Thread safety
    mutable std::shared_mutex rwLock_;
    
    // Performance tracking
    mutable Stats stats_{};
    
    // Internal helpers
    void updateAddressRange();
    void rebuildAddressCache();
    size_t binarySearchAddress(uint64_t address) const;
    void analyzeJumpsInternal();
    uint8_t parseInstructionType(const char* mnemonic) const;
    uint64_t parseJumpTarget(const char* operands) const;
};

} // namespace MacDBG
