import Foundation
import MLXLLM
import MLXLMCommon
import MLX

class LocalLLM {
    private static var gpuCacheLimitSet = false
    
    /// Calculate GPU cache limit based on available system memory.
    /// Uses ~7% of total memory, clamped between 32MB and 4GB.
    private static func calculateGPUCacheLimit() -> Int {
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        let cacheLimit = Int(Double(totalMemory) * 0.07)
        let minCache = 32 * 1024 * 1024           // 32 MB
        let maxCache = 4 * 1024 * 1024 * 1024     // 4 GB
        return min(max(cacheLimit, minCache), maxCache)
    }
    
    private static func setupGPUCacheLimitOnce() {
        guard !gpuCacheLimitSet else { return }
        gpuCacheLimitSet = true
        
        let cacheLimit = calculateGPUCacheLimit()
        MLX.GPU.set(cacheLimit: cacheLimit)
        Logger.log("GPU cache limit set to \(GenericHelper.formatSize(size: Int64(cacheLimit)))", log: Logger.general)
    }
    
    static func loadModel(modelRepo: String, modelName: String) async throws -> ModelContainer {
        let modelPath = try await ModelStorage.shared.getModelPath(modelRepo: modelRepo, modelName: modelName)

        setupGPUCacheLimitOnce()

        Logger.log("Loading model \(modelRepo)/\(modelName)", log: Logger.general)

        var modelConfiguration: ModelConfiguration
        switch modelRepo {
        case MlxCommunityRepo + "/" + Gemma_2_9b_it_4bit:
            modelConfiguration = LLMRegistry.gemma_2_9b_it_4bit
        case MlxCommunityRepo + "/" + Meta_Llama_3_8B_Instruct_4bit:
            modelConfiguration = LLMRegistry.llama3_1_8B_4bit
        case MlxCommunityRepo + "/" + DeepSeek_R1_Distill_Qwen_7B_4bit:
            modelConfiguration = LLMRegistry.deepSeekR1_7B_4bit
        case MlxCommunityRepo + "/" + Mistral_7B_Instruct_v0_3_4bit:
            modelConfiguration = LLMRegistry.mistral7B4bit
        case MlxCommunityRepo + "/" + Qwen_3_8B_4bit:
            modelConfiguration = LLMRegistry.qwen3_8b_4bit
        case MlxCommunityRepo + "/" + Gemma_2_2b_it_4bit:
            modelConfiguration = LLMRegistry.gemma_2_2b_it_4bit
        case MlxCommunityRepo + "/" + Qwen2_5_1_5B_Instruct_4bit:
            modelConfiguration = LLMRegistry.qwen2_5_1_5b
        case MlxCommunityRepo + "/" + Phi_3_5_mini_instruct_4bit:
            modelConfiguration = LLMRegistry.phi3_5_4bit
        case MlxCommunityRepo + "/" + Llama_3_2_3B_Instruct_4bit:
            modelConfiguration = LLMRegistry.llama3_2_3B_4bit
        case MlxCommunityRepo + "/" + Qwen3_4B_4bit:
            modelConfiguration = LLMRegistry.qwen3_4b_4bit
        default:
            throw NSError(domain: "TextEnhancer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unsupported model"])
        }

        modelConfiguration.id = .directory(modelPath)

        let modelContainer = try await LLMModelFactory.shared.loadContainer(configuration: modelConfiguration)
        Logger.log("Model \(modelRepo)/\(modelName) loaded", log: Logger.general)
        return modelContainer
    }

    static func generate(modelContainer: ModelContainer, systemPrompt: String, userPrompt: String) async throws -> String {
        if GenericHelper.logSensitiveData() {
            Logger.log("Generating text with system prompt: \(systemPrompt) and user prompt: \(userPrompt)", log: Logger.general)
        }

        var chat: [Chat.Message] = []
        if systemPrompt != "" {
            chat.append(.system(systemPrompt))
        }
        chat.append(.user(userPrompt))

        let userInput = UserInput(
            chat: chat, additionalContext: ["enable_thinking": false])

        let outputActor = OutputActor()
        let generateParameters = GenerateParameters(maxTokens: 8192, temperature: 0.6)
        try await modelContainer.perform { (context: ModelContext) -> Void in
            let lmInput = try await context.processor.prepare(input: userInput)

            for await generation in try MLXLMCommon.generate(input: lmInput, parameters: generateParameters, context: context) {
                switch generation {
                case .chunk(let chunk):
                    await outputActor.append(chunk)
                default:
                    break
                }
            }
        }
        let text = await outputActor.getOutput()
        if GenericHelper.logSensitiveData() {
            Logger.log("Generated text: \(text)", log: Logger.general)
        }
        return text
    }
}

private actor OutputActor {
    private var output: String = ""

    func append(_ chunk: String) {
        output += chunk
    }

    func getOutput() -> String {
        return output
    }
}
