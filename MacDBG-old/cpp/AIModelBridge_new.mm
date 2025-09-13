#import "AIModelBridge.hpp"
#import "AIModelManager.hpp"
#import <Foundation/Foundation.h>

@implementation AIModelBridge {
    AIModelManager* _modelManager;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _modelManager = new AIModelManager();
    }
    return self;
}

- (void)dealloc {
    if (_modelManager) {
        delete _modelManager;
        _modelManager = nullptr;
    }
}

- (BOOL)loadModel:(NSString *)modelPath {
    if (!_modelManager) {
        return NO;
    }
    
    std::string cppPath = [modelPath UTF8String];
    return _modelManager->loadModel(cppPath);
}

- (void)unloadModel {
    if (_modelManager) {
        _modelManager->unloadModel();
    }
}

- (BOOL)isModelLoaded {
    if (!_modelManager) {
        return NO;
    }
    
    return _modelManager->isModelLoaded();
}

- (NSString *)generateText:(NSString *)prompt maxTokens:(int)maxTokens {
    if (!_modelManager || !_modelManager->isModelLoaded()) {
        return @"Error: No model loaded";
    }
    
    std::string cppPrompt = [prompt UTF8String];
    std::string result = _modelManager->generateText(cppPrompt, maxTokens);
    
    return [NSString stringWithUTF8String:result.c_str()];
}

- (NSString *)generateCodeAnalysis:(NSString *)disassembly context:(NSString *)context {
    if (!_modelManager || !_modelManager->isModelLoaded()) {
        return @"Error: No model loaded";
    }
    
    std::string cppDisassembly = [disassembly UTF8String];
    std::string cppContext = [context UTF8String];
    std::string result = _modelManager->generateCodeAnalysis(cppDisassembly, cppContext);
    
    return [NSString stringWithUTF8String:result.c_str()];
}

- (NSString *)generateComment:(NSString *)instruction context:(NSString *)context {
    if (!_modelManager || !_modelManager->isModelLoaded()) {
        return @"Error: No model loaded";
    }
    
    std::string cppInstruction = [instruction UTF8String];
    std::string cppContext = [context UTF8String];
    std::string result = _modelManager->generateComment(cppInstruction, cppContext);
    
    return [NSString stringWithUTF8String:result.c_str()];
}

- (NSString *)generateBreakpointSuggestion:(NSString *)code context:(NSString *)context {
    if (!_modelManager || !_modelManager->isModelLoaded()) {
        return @"Error: No model loaded";
    }
    
    std::string cppCode = [code UTF8String];
    std::string cppContext = [context UTF8String];
    std::string result = _modelManager->generateBreakpointSuggestion(cppCode, cppContext);
    
    return [NSString stringWithUTF8String:result.c_str()];
}

- (void)generateTextAsync:(NSString *)prompt 
               maxTokens:(int)maxTokens 
              completion:(void(^)(NSString *))completion {
    if (!_modelManager || !_modelManager->isModelLoaded()) {
        if (completion) {
            completion(@"Error: No model loaded");
        }
        return;
    }
    
    std::string cppPrompt = [prompt UTF8String];
    
    _modelManager->generateTextAsync(cppPrompt, [completion](const std::string& result) {
        NSString* nsResult = [NSString stringWithUTF8String:result.c_str()];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                completion(nsResult);
            }
        });
    }, maxTokens);
}

- (void)setTemperature:(float)temperature {
    if (_modelManager) {
        _modelManager->setTemperature(temperature);
    }
}

- (void)setTopP:(float)topP {
    if (_modelManager) {
        _modelManager->setTopP(topP);
    }
}

- (void)setMaxTokens:(int)maxTokens {
    if (_modelManager) {
        _modelManager->setMaxTokens(maxTokens);
    }
}

- (NSString *)getModelName {
    if (!_modelManager) {
        return @"No model";
    }
    
    std::string name = _modelManager->getModelName();
    return [NSString stringWithUTF8String:name.c_str()];
}

- (NSUInteger)getModelSize {
    if (!_modelManager) {
        return 0;
    }
    
    return _modelManager->getModelSize();
}

- (int)getContextLength {
    if (!_modelManager) {
        return 0;
    }
    
    return _modelManager->getContextLength();
}

@end
