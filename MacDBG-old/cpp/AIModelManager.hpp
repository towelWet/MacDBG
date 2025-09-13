#ifndef AIModelManager_hpp
#define AIModelManager_hpp

#include <string>
#include <vector>
#include <memory>
#include <functional>
#include <mutex>

// Using external llama-cli binary for text generation

class AIModelManager {
public:
    AIModelManager();
    ~AIModelManager();
    
    // Model management
    bool loadModel(const std::string& modelPath);
    void unloadModel();
    bool isModelLoaded() const;
    
    // Text generation
    std::string generateText(const std::string& prompt, int maxTokens = 512);
    std::string generateCodeAnalysis(const std::string& disassembly, const std::string& context = "");
    std::string generateComment(const std::string& instruction, const std::string& context = "");
    std::string generateBreakpointSuggestion(const std::string& code, const std::string& context = "");
    
    // Async generation with callback
    void generateTextAsync(const std::string& prompt, 
                          std::function<void(const std::string&)> completion,
                          int maxTokens = 512);
    
    // Configuration
    void setTemperature(float temperature);
    void setTopP(float topP);
    void setMaxTokens(int maxTokens);
    
    // Model info
    std::string getModelName() const;
    size_t getModelSize() const;
    int getContextLength() const;

private:
    bool initializeLlama();
    void cleanupLlama();
    std::string processTokens(const std::vector<int>& tokens);
    
    // No internal llama.cpp pointers needed (using external llama-cli)
    
    bool modelLoaded_;
    std::string modelPath_;
    std::string modelName_;
    
    // Generation parameters
    float temperature_;
    float topP_;
    int maxTokens_;
    int contextLength_;
    
    // Thread safety
    mutable std::mutex modelMutex_;
};

#endif /* AIModelManager_hpp */
