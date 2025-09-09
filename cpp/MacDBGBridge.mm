#import "MacDBGBridge.hpp"
#include <memory>

using namespace MacDBG;

// C Interface Implementation
extern "C" {

void* macdbg_create_engine(void) {
    return new DisassemblyEngine();
}

void macdbg_destroy_engine(void* engine) {
    delete static_cast<DisassemblyEngine*>(engine);
}

void macdbg_set_instructions_from_lldb(void* engine,
                                      const uint64_t* addresses,
                                      const char** mnemonics,
                                      const char** operands,
                                      const char** bytes,
                                      const uint32_t* sizes,
                                      size_t count) {
    auto* eng = static_cast<DisassemblyEngine*>(engine);
    std::vector<Instruction> instructions;
    instructions.reserve(count);
    
    for (size_t i = 0; i < count; ++i) {
        Instruction inst = {};
        inst.address = addresses[i];
        inst.size = sizes[i];
        inst.jumpTargetIndex = UINT32_MAX;
        
        // Copy strings with bounds checking
        strncpy(inst.mnemonic, mnemonics[i], sizeof(inst.mnemonic) - 1);
        strncpy(inst.operands, operands[i], sizeof(inst.operands) - 1);
        strncpy(inst.bytes, bytes[i], sizeof(inst.bytes) - 1);
        inst.bytesLength = static_cast<uint8_t>(strlen(inst.bytes));
        
        instructions.push_back(inst);
    }
    
    eng->setInstructions(instructions);
}

void macdbg_append_instructions(void* engine,
                               const uint64_t* addresses,
                               const char** mnemonics,
                               const char** operands,
                               const char** bytes,
                               const uint32_t* sizes,
                               size_t count) {
    auto* eng = static_cast<DisassemblyEngine*>(engine);
    std::vector<Instruction> instructions;
    instructions.reserve(count);
    
    for (size_t i = 0; i < count; ++i) {
        Instruction inst = {};
        inst.address = addresses[i];
        inst.size = sizes[i];
        inst.jumpTargetIndex = UINT32_MAX;
        
        strncpy(inst.mnemonic, mnemonics[i], sizeof(inst.mnemonic) - 1);
        strncpy(inst.operands, operands[i], sizeof(inst.operands) - 1);
        strncpy(inst.bytes, bytes[i], sizeof(inst.bytes) - 1);
        inst.bytesLength = static_cast<uint8_t>(strlen(inst.bytes));
        
        instructions.push_back(inst);
    }
    
    eng->appendInstructions(instructions);
}

size_t macdbg_get_instruction_count(void* engine) {
    return static_cast<DisassemblyEngine*>(engine)->getInstructionCount();
}

size_t macdbg_find_index_by_address(void* engine, uint64_t address) {
    return static_cast<DisassemblyEngine*>(engine)->findIndexByAddress(address);
}

size_t macdbg_get_visible_instructions(void* engine,
                                      size_t startIndex,
                                      size_t maxCount,
                                      SwiftInstruction* outInstructions) {
    auto* eng = static_cast<DisassemblyEngine*>(engine);
    auto instructions = eng->getVisibleRange(startIndex, maxCount);
    
    size_t count = 0;
    for (const auto* inst : instructions) {
        if (count >= maxCount) break;
        
        SwiftInstruction& swiftInst = outInstructions[count];
        swiftInst.address = inst->address;
        swiftInst.size = inst->size;
        swiftInst.hasJumpTarget = (inst->jumpTargetIndex != UINT32_MAX);
        swiftInst.instructionType = inst->instructionType;
        
        // Pre-format address for UI performance
        snprintf(swiftInst.formattedAddress, sizeof(swiftInst.formattedAddress),
                "0x%016llx", inst->address);
        
        // Copy strings
        strncpy(swiftInst.bytes, inst->bytes, sizeof(swiftInst.bytes) - 1);
        strncpy(swiftInst.mnemonic, inst->mnemonic, sizeof(swiftInst.mnemonic) - 1);
        strncpy(swiftInst.operands, inst->operands, sizeof(swiftInst.operands) - 1);
        
        // Get jump target if exists
        if (swiftInst.hasJumpTarget) {
            // This requires accessing jumpTargets_ - would need a getter method
            swiftInst.jumpTargetAddress = 0; // Placeholder
        } else {
            swiftInst.jumpTargetAddress = 0;
        }
        
        count++;
    }
    
    return count;
}

void macdbg_analyze_jumps_async(void* engine) {
    static_cast<DisassemblyEngine*>(engine)->analyzeJumps();
}

bool macdbg_has_jump_target(void* engine, uint64_t address) {
    auto* eng = static_cast<DisassemblyEngine*>(engine);
    const Instruction* inst = eng->findByAddress(address);
    return inst && inst->jumpTargetIndex != UINT32_MAX;
}

uint64_t macdbg_get_jump_target(void* engine, uint64_t address) {
    auto* eng = static_cast<DisassemblyEngine*>(engine);
    const Instruction* inst = eng->findByAddress(address);
    if (!inst || inst->jumpTargetIndex == UINT32_MAX) {
        return 0;
    }
    
    // Would need a method to get jump target by index
    return 0; // Placeholder
}

void macdbg_get_stats(void* engine,
                     uint64_t* instructionCount,
                     uint64_t* jumpCount,
                     uint64_t* analysisTimeUs,
                     uint64_t* lastLookupTimeNs) {
    auto stats = static_cast<DisassemblyEngine*>(engine)->getStats();
    *instructionCount = stats.instructionCount;
    *jumpCount = stats.jumpCount;
    *analysisTimeUs = stats.analysisTimeUs;
    *lastLookupTimeNs = stats.lastLookupTimeNs;
}

} // extern "C"

// Objective-C++ Implementation
@implementation MacDBGEngine {
    DisassemblyEngine* _engine;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _engine = new DisassemblyEngine();
    }
    return self;
}

- (void)dealloc {
    delete _engine;
}

- (void)setInstructionsFromLLDB:(NSArray<NSDictionary*>*)instructions {
    std::vector<Instruction> cppInstructions;
    cppInstructions.reserve(instructions.count);
    
    for (NSDictionary* dict in instructions) {
        Instruction inst = {};
        inst.address = [dict[@"address"] unsignedLongLongValue];
        inst.size = [dict[@"size"] unsignedIntValue];
        inst.jumpTargetIndex = UINT32_MAX;
        
        NSString* mnemonic = dict[@"mnemonic"] ?: @"";
        NSString* operands = dict[@"operands"] ?: @"";
        NSString* bytes = dict[@"bytes"] ?: @"";
        
        strncpy(inst.mnemonic, mnemonic.UTF8String, sizeof(inst.mnemonic) - 1);
        strncpy(inst.operands, operands.UTF8String, sizeof(inst.operands) - 1);
        strncpy(inst.bytes, bytes.UTF8String, sizeof(inst.bytes) - 1);
        inst.bytesLength = static_cast<uint8_t>(strlen(inst.bytes));
        
        cppInstructions.push_back(inst);
    }
    
    _engine->setInstructions(cppInstructions);
}

- (void)appendInstructions:(NSArray<NSDictionary*>*)instructions {
    std::vector<Instruction> cppInstructions;
    cppInstructions.reserve(instructions.count);
    
    for (NSDictionary* dict in instructions) {
        Instruction inst = {};
        inst.address = [dict[@"address"] unsignedLongLongValue];
        inst.size = [dict[@"size"] unsignedIntValue];
        inst.jumpTargetIndex = UINT32_MAX;
        
        NSString* mnemonic = dict[@"mnemonic"] ?: @"";
        NSString* operands = dict[@"operands"] ?: @"";
        NSString* bytes = dict[@"bytes"] ?: @"";
        
        strncpy(inst.mnemonic, mnemonic.UTF8String, sizeof(inst.mnemonic) - 1);
        strncpy(inst.operands, operands.UTF8String, sizeof(inst.operands) - 1);
        strncpy(inst.bytes, bytes.UTF8String, sizeof(inst.bytes) - 1);
        inst.bytesLength = static_cast<uint8_t>(strlen(inst.bytes));
        
        cppInstructions.push_back(inst);
    }
    
    _engine->appendInstructions(cppInstructions);
}

- (NSUInteger)instructionCount {
    return _engine->getInstructionCount();
}

- (NSUInteger)findIndexByAddress:(uint64_t)address {
    return _engine->findIndexByAddress(address);
}

- (NSArray<NSDictionary*>*)getVisibleInstructions:(NSUInteger)startIndex count:(NSUInteger)count {
    // Pre-allocate C array for performance
    auto swiftInstructions = std::make_unique<SwiftInstruction[]>(count);
    size_t actualCount = macdbg_get_visible_instructions(_engine, startIndex, count, swiftInstructions.get());
    
    NSMutableArray* result = [[NSMutableArray alloc] initWithCapacity:actualCount];
    
    for (size_t i = 0; i < actualCount; ++i) {
        const SwiftInstruction& inst = swiftInstructions[i];
        
        [result addObject:@{
            @"address": @(inst.address),
            @"formattedAddress": [NSString stringWithUTF8String:inst.formattedAddress],
            @"bytes": [NSString stringWithUTF8String:inst.bytes],
            @"mnemonic": [NSString stringWithUTF8String:inst.mnemonic],
            @"operands": [NSString stringWithUTF8String:inst.operands],
            @"size": @(inst.size),
            @"hasJumpTarget": @(inst.hasJumpTarget),
            @"jumpTargetAddress": @(inst.jumpTargetAddress),
            @"instructionType": @(inst.instructionType)
        }];
    }
    
    return result;
}

- (void)analyzeJumpsAsync {
    _engine->analyzeJumps();
}

- (BOOL)hasJumpTarget:(uint64_t)address {
    return macdbg_has_jump_target(_engine, address);
}

- (uint64_t)getJumpTarget:(uint64_t)address {
    return macdbg_get_jump_target(_engine, address);
}

- (NSDictionary*)getPerformanceStats {
    uint64_t instructionCount, jumpCount, analysisTimeUs, lastLookupTimeNs;
    macdbg_get_stats(_engine, &instructionCount, &jumpCount, &analysisTimeUs, &lastLookupTimeNs);
    
    return @{
        @"instructionCount": @(instructionCount),
        @"jumpCount": @(jumpCount),
        @"analysisTimeUs": @(analysisTimeUs),
        @"lastLookupTimeNs": @(lastLookupTimeNs)
    };
}

@end
