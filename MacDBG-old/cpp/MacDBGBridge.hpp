#pragma once
#include "DisassemblyEngine.hpp"
#include <Foundation/Foundation.h>

// Swift-compatible instruction data (minimal for UI)
struct SwiftInstruction {
    uint64_t address;
    uint32_t size;
    bool hasJumpTarget;
    uint64_t jumpTargetAddress;
    uint8_t instructionType;
    char formattedAddress[20];    // Pre-formatted for UI
    char bytes[32];               // Pre-formatted hex string
    char mnemonic[12];
    char operands[64];
};

// C interface for Swift bridging
extern "C" {
    // Engine lifecycle
    void* macdbg_create_engine(void);
    void macdbg_destroy_engine(void* engine);
    
    // Instruction management
    void macdbg_set_instructions_from_lldb(void* engine, 
                                          const uint64_t* addresses,
                                          const char** mnemonics,
                                          const char** operands,
                                          const char** bytes,
                                          const uint32_t* sizes,
                                          size_t count);
    
    void macdbg_append_instructions(void* engine,
                                   const uint64_t* addresses,
                                   const char** mnemonics, 
                                   const char** operands,
                                   const char** bytes,
                                   const uint32_t* sizes,
                                   size_t count);
    
    // Fast UI queries
    size_t macdbg_get_instruction_count(void* engine);
    size_t macdbg_find_index_by_address(void* engine, uint64_t address);
    
    // Get visible range for UI (pre-formatted, ready for SwiftUI)
    size_t macdbg_get_visible_instructions(void* engine,
                                          size_t startIndex,
                                          size_t maxCount,
                                          SwiftInstruction* outInstructions);
    
    // Jump analysis
    void macdbg_analyze_jumps_async(void* engine);
    bool macdbg_has_jump_target(void* engine, uint64_t address);
    uint64_t macdbg_get_jump_target(void* engine, uint64_t address);
    
    // Performance stats
    void macdbg_get_stats(void* engine,
                         uint64_t* instructionCount,
                         uint64_t* jumpCount,
                         uint64_t* analysisTimeUs,
                         uint64_t* lastLookupTimeNs);
}

// Objective-C++ wrapper for Swift integration
@interface MacDBGEngine : NSObject

- (instancetype)init;
- (void)dealloc;

// Core operations
- (void)setInstructionsFromLLDB:(NSArray<NSDictionary*>*)instructions;
- (void)appendInstructions:(NSArray<NSDictionary*>*)instructions;

// UI queries
- (NSUInteger)instructionCount;
- (NSUInteger)findIndexByAddress:(uint64_t)address;
- (NSArray<NSDictionary*>*)getVisibleInstructions:(NSUInteger)startIndex count:(NSUInteger)count;

// Jump operations
- (void)analyzeJumpsAsync;
- (BOOL)hasJumpTarget:(uint64_t)address;
- (uint64_t)getJumpTarget:(uint64_t)address;

// Performance monitoring
- (NSDictionary*)getPerformanceStats;

@end
