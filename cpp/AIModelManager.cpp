#include "AIModelManager.hpp"
#include <iostream>
#include <fstream>
#include <sstream>
#include <thread>
#include <mutex>
#include <algorithm>
#include <cstring>

// Real llama.cpp integration via external llama-cli binary

AIModelManager::AIModelManager() 
    : modelLoaded_(false)
    , temperature_(0.7f)
    , topP_(0.9f)
    , maxTokens_(512)
    , contextLength_(2048)
{
    initializeLlama();
}

AIModelManager::~AIModelManager() {
    cleanupLlama();
}

bool AIModelManager::initializeLlama() {
    // Check if llama-cli is available
    int result = system("/usr/local/Cellar/llama.cpp/6390/bin/llama-cli --help >/dev/null 2>&1");
    if (result != 0) {
        std::cerr << "AI Model Manager: llama-cli not found or not executable" << std::endl;
        return false;
    }
    
    std::cout << "AI Model Manager: llama-cli backend ready for real text generation" << std::endl;
    return true;
}

void AIModelManager::cleanupLlama() {
    unloadModel();
    // No cleanup needed for external llama-cli
}

bool AIModelManager::loadModel(const std::string& modelPath) {
    std::lock_guard<std::mutex> lock(modelMutex_);
    
    if (modelLoaded_) {
        unloadModel();
    }
    
    // Check if model file exists
    std::ifstream file(modelPath);
    if (!file.good()) {
        std::cerr << "AI Model Manager: Model file not found: " << modelPath << std::endl;
        return false;
    }
    
    modelPath_ = modelPath;
    
    // Extract model name from path
    size_t lastSlash = modelPath.find_last_of("/\\");
    if (lastSlash != std::string::npos) {
        modelName_ = modelPath.substr(lastSlash + 1);
    } else {
        modelName_ = modelPath;
    }
    
    std::cout << "AI Model Manager: Preparing GGUF model: " << modelName_ << std::endl;
    std::cout << "AI Model Manager: Model path: " << modelPath << std::endl;
    
    // Test that llama-cli can access the model
    std::ostringstream test_cmd;
    test_cmd << "/usr/local/Cellar/llama.cpp/6390/bin/llama-cli";
    test_cmd << " -m \"" << modelPath << "\"";
    test_cmd << " -p \"test\"";
    test_cmd << " -n 1";
    test_cmd << " 2>/dev/null >/dev/null"; // Suppress all output
    
    int test_result = system(test_cmd.str().c_str());
    if (test_result != 0) {
        std::cerr << "Failed to validate GGUF model with llama-cli" << std::endl;
        return false;
    }
    
    modelLoaded_ = true;
    std::cout << "AI Model Manager: GGUF model validated and ready for real text generation!" << std::endl;
    
    return true;
}

void AIModelManager::unloadModel() {
    std::lock_guard<std::mutex> lock(modelMutex_);
    
    if (!modelLoaded_) {
        return;
    }
    
    // No complex cleanup needed since we use llama-cli externally
    modelLoaded_ = false;
    modelPath_.clear();
    modelName_.clear();
    
    std::cout << "AI Model Manager: GGUF model unloaded" << std::endl;
}

bool AIModelManager::isModelLoaded() const {
    std::lock_guard<std::mutex> lock(modelMutex_);
    return modelLoaded_;
}

std::string AIModelManager::generateText(const std::string& prompt, int maxTokens) {
    std::lock_guard<std::mutex> lock(modelMutex_);
    
    if (!modelLoaded_) {
        return "Error: No model loaded";
    }
    
    std::cout << "AI Model Manager: Generating real text using llama-cli for prompt: " << prompt.substr(0, 50) << "..." << std::endl;
    
    // Use llama-cli binary to generate text with the loaded model
    // This is simpler and more reliable than implementing the complex llama.cpp API
    
    // Create a temporary file for the prompt
    std::string temp_prompt_file = "/tmp/macdbg_prompt.txt";
    std::ofstream prompt_file(temp_prompt_file);
    if (!prompt_file.is_open()) {
        return "Error: Could not create temporary prompt file";
    }
    prompt_file << prompt;
    prompt_file.close();
    
    // Construct the llama-cli command
    std::ostringstream cmd;
    cmd << "/usr/local/Cellar/llama.cpp/6390/bin/llama-cli";
    cmd << " -m \"" << modelPath_ << "\"";
    cmd << " -p \"" << prompt << "\"";
    cmd << " -n " << maxTokens;
    cmd << " --temp 0.7";
    cmd << " --top-p 0.9";
    cmd << " --repeat-penalty 1.1";
    cmd << " --ctx-size 2048";
    cmd << " 2>/dev/null"; // Suppress stderr
    
    std::cout << "AI Model Manager: Running command: " << cmd.str().substr(0, 100) << "..." << std::endl;
    
    // Execute the command and capture output
    FILE* pipe = popen(cmd.str().c_str(), "r");
    if (!pipe) {
        return "Error: Failed to execute llama-cli";
    }
    
    std::string response;
    char buffer[4096];
    while (fgets(buffer, sizeof(buffer), pipe) != nullptr) {
        response += buffer;
    }
    
    int exit_code = pclose(pipe);
    
    // Clean up temporary file
    std::remove(temp_prompt_file.c_str());
    
    if (exit_code != 0) {
        return "Error: llama-cli execution failed with code " + std::to_string(exit_code);
    }
    
    // Remove the prompt echo from the response (llama-cli often echoes the prompt)
    size_t prompt_end = response.find(prompt);
    if (prompt_end != std::string::npos) {
        response = response.substr(prompt_end + prompt.length());
    }
    
    // Remove common llama-cli artifacts and control text
    std::vector<std::string> artifacts = {
        "EOF by user",
        "> EOF by user",
        "assistant ",
        "user:",
        "assistant:",
        "> ",
        "User:",
        "Assistant:",
        "\n\n> ",
        "\n> ",
        ">EOF",
        "EOF"
    };
    
    for (const auto& artifact : artifacts) {
        size_t pos = 0;
        while ((pos = response.find(artifact, pos)) != std::string::npos) {
            response.erase(pos, artifact.length());
        }
    }
    
    // Remove lines that start with ">" (common in llama-cli output)
    std::istringstream iss(response);
    std::ostringstream cleaned;
    std::string line;
    
    while (std::getline(iss, line)) {
        // Skip lines that start with ">" or are empty/whitespace
        if (!line.empty() && line[0] != '>' && line.find_first_not_of(" \t\n\r") != std::string::npos) {
            cleaned << line << "\n";
        }
    }
    
    response = cleaned.str();
    
    // Trim whitespace
    size_t start = response.find_first_not_of(" \t\n\r");
    if (start != std::string::npos) {
        response = response.substr(start);
    }
    
    size_t end = response.find_last_not_of(" \t\n\r");
    if (end != std::string::npos) {
        response = response.substr(0, end + 1);
    }
    
    std::cout << "AI Model Manager: Generated real response: " << response.substr(0, 100) << "..." << std::endl;
    return response.empty() ? "Error: No response generated" : response;
}

std::string AIModelManager::generateCodeAnalysis(const std::string& disassembly, const std::string& context) {
    std::string prompt = "Analyze this assembly code and provide insights:\n\n";
    prompt += "Context: " + context + "\n\n";
    prompt += "Assembly:\n" + disassembly + "\n\n";
    prompt += "Please provide:\n";
    prompt += "1. What this code does\n";
    prompt += "2. Potential vulnerabilities\n";
    prompt += "3. Optimization suggestions\n";
    prompt += "4. Register usage analysis\n";
    
    return generateText(prompt, 1024);
}

std::string AIModelManager::generateComment(const std::string& instruction, const std::string& context) {
    std::string prompt = "Add a detailed comment for this assembly instruction:\n\n";
    prompt += "Context: " + context + "\n\n";
    prompt += "Instruction: " + instruction + "\n\n";
    prompt += "Provide a clear, technical comment explaining what this instruction does:";
    
    return generateText(prompt, 256);
}

std::string AIModelManager::generateBreakpointSuggestion(const std::string& code, const std::string& context) {
    std::string prompt = "Suggest optimal breakpoint locations for debugging this code:\n\n";
    prompt += "Context: " + context + "\n\n";
    prompt += "Code:\n" + code + "\n\n";
    prompt += "Suggest specific addresses and explain why each breakpoint would be useful:";
    
    return generateText(prompt, 512);
}

void AIModelManager::generateTextAsync(const std::string& prompt, 
                                     std::function<void(const std::string&)> completion,
                                     int maxTokens) {
    // Run generation in background thread
    std::thread([this, prompt, completion, maxTokens]() {
        std::string result = generateText(prompt, maxTokens);
        completion(result);
    }).detach();
}

void AIModelManager::setTemperature(float temperature) {
    std::lock_guard<std::mutex> lock(modelMutex_);
    temperature_ = std::max(0.0f, std::min(2.0f, temperature));
}

void AIModelManager::setTopP(float topP) {
    std::lock_guard<std::mutex> lock(modelMutex_);
    topP_ = std::max(0.0f, std::min(1.0f, topP));
}

void AIModelManager::setMaxTokens(int maxTokens) {
    std::lock_guard<std::mutex> lock(modelMutex_);
    maxTokens_ = std::max(1, std::min(4096, maxTokens));
}

std::string AIModelManager::getModelName() const {
    std::lock_guard<std::mutex> lock(modelMutex_);
    return modelName_;
}

size_t AIModelManager::getModelSize() const {
    // TODO: Return actual model size
    return 0;
}

int AIModelManager::getContextLength() const {
    return contextLength_;
}

std::string AIModelManager::processTokens(const std::vector<int>& tokens) {
    // TODO: Implement token processing
    // This would convert token IDs back to text
    return "Token processing not implemented";
}
