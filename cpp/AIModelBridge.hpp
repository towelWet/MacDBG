#ifndef AIModelBridge_hpp
#define AIModelBridge_hpp

#import <Foundation/Foundation.h>

// Swift-compatible interface for AI Model Manager
@interface AIModelBridge : NSObject

// Model management
- (BOOL)loadModel:(NSString *)modelPath;
- (void)unloadModel;
- (BOOL)isModelLoaded;

// Text generation
- (NSString *)generateText:(NSString *)prompt maxTokens:(int)maxTokens;
- (NSString *)generateCodeAnalysis:(NSString *)disassembly context:(NSString *)context;
- (NSString *)generateComment:(NSString *)instruction context:(NSString *)context;
- (NSString *)generateBreakpointSuggestion:(NSString *)code context:(NSString *)context;

// Async generation
- (void)generateTextAsync:(NSString *)prompt 
               maxTokens:(int)maxTokens 
              completion:(void(^)(NSString *))completion;

// Configuration
- (void)setTemperature:(float)temperature;
- (void)setTopP:(float)topP;
- (void)setMaxTokens:(int)maxTokens;

// Model info
- (NSString *)getModelName;
- (NSUInteger)getModelSize;
- (int)getContextLength;

@end

#endif /* AIModelBridge_hpp */
