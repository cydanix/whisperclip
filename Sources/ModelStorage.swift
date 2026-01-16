import Foundation
import WhisperKit
import FluidAudio

class ModelStorage {
    static let shared = ModelStorage()
    private let downloader: ModelDownloader
    private let digestFileName = "whisperclip.digest"
    private let loadedMarkerFileName = "whisperclip.loaded"

    private init() {
        self.downloader = ModelDownloader(downloadBase: GenericHelper.getAppSupportDirectory())
    }

    func getModelFilesUrl(modelID: String, subfolder: String) -> String {
        return "https://hf.co/\(modelID)/tree/main/\(subfolder)"
    }

    func getModelID(modelRepo: String, modelName: String) -> String {
        if modelName != "" {
            return modelRepo + "/" + modelName
        } else {
            return modelRepo
        }
    }

    func preLoadModel(modelRepo: String, modelName: String) async throws {
        Logger.log("Loading model \(modelRepo)/\(modelName)", log: Logger.general)

        switch modelRepo {
        case WhisperKitRepo:
            let _ = try await LocalWhisperKit.loadModel(modelRepo: modelRepo, modelName: modelName)
        case MlxCommunityRepo + "/" + Gemma_2_9b_it_4bit,
             MlxCommunityRepo + "/" + Meta_Llama_3_8B_Instruct_4bit,
             MlxCommunityRepo + "/" + DeepSeek_R1_Distill_Qwen_7B_4bit,
             MlxCommunityRepo + "/" + Mistral_7B_Instruct_v0_3_4bit,
             MlxCommunityRepo + "/" + Qwen_3_8B_4bit,
             MlxCommunityRepo + "/" + Gemma_2_2b_it_4bit,
             MlxCommunityRepo + "/" + Qwen2_5_1_5B_Instruct_4bit,
             MlxCommunityRepo + "/" + Phi_3_5_mini_instruct_4bit,
             MlxCommunityRepo + "/" + Llama_3_2_3B_Instruct_4bit,
             MlxCommunityRepo + "/" + Qwen3_4B_4bit:
            let modelContainer = try await LocalLLM.loadModel(modelRepo: modelRepo, modelName: modelName)
            Logger.log("Model \(modelRepo)/\(modelName) loaded", log: Logger.general)

            var systemPrompt = "You are a helpful assistant."
            switch modelRepo {
            case MlxCommunityRepo + "/" + Gemma_2_2b_it_4bit,
                 MlxCommunityRepo + "/" + Gemma_2_9b_it_4bit,
                 MlxCommunityRepo + "/" + Mistral_7B_Instruct_v0_3_4bit:
                systemPrompt = ""
            default:
                break
            }

            let result = try await LocalLLM.generate(modelContainer: modelContainer,
                                    systemPrompt: systemPrompt,
                                    userPrompt: "What is the capital of France?")
            Logger.log("Generated text: \(result)", log: Logger.general)
        default:
            break
        }
        Logger.log("Model \(modelRepo)/\(modelName) loaded", log: Logger.general)

        let modelLoadedMarkerFilePath = getModelLoadedMarkerFilePath(modelRepo: modelRepo, modelName: modelName)
        if !FileManager.default.fileExists(atPath: modelLoadedMarkerFilePath) {
            FileManager.default.createFile(atPath: modelLoadedMarkerFilePath, contents: nil, attributes: nil)
        }
    }

    func getModelLoadedMarkerFilePath(modelRepo: String, modelName: String) -> String {
        return getModelDir(modelRepo: modelRepo, modelName: modelName).appendingPathComponent(loadedMarkerFileName).path
    }

    func isModelLoaded(modelRepo: String, modelName: String) -> Bool {
        return FileManager.default.fileExists(atPath: getModelLoadedMarkerFilePath(modelRepo: modelRepo, modelName: modelName))
    }

    func downloadModel(modelRepo: String, modelName: String, progress: @escaping (Double) -> Void) async throws -> URL {
        try GenericHelper.folderCreate(folder: downloader.downloadBase)

        let freeSpace = GenericHelper.getFreeDiskSpace(path: downloader.downloadBase)
        if freeSpace < MinimalFreeDiskSpace {
            let shouldContinue = await WhisperClip.shared?.showNoEnoughDiskSpaceAlert(freeSpace: freeSpace) ?? false
            if !shouldContinue {
                throw NSError(domain: "ModelStorage", code: 2, userInfo: [NSLocalizedDescriptionKey: "Not enough disk space. Required: 20GB, Available: \(GenericHelper.formatSize(size: freeSpace))"])
            }
        }

        let modelDir = getModelDir(modelRepo: modelRepo, modelName: modelName)
        if GenericHelper.folderExists(folder: modelDir) {
            try deleteModel(modelRepo: modelRepo, modelName: modelName)
        }

        Logger.log("Downloading model modelRepo: \(modelRepo), modelName: \(modelName)...", log: Logger.general)
        let modelPath = try await downloader.downloadSubfolder(modelID: modelRepo, subfolder: modelName, progress: progress)
        Logger.log("Model modelRepo: \(modelRepo), modelName: \(modelName) downloaded to \(modelPath.path)", log: Logger.general)

        let hash = try GenericHelper.getDirectoryHash(ofDirectory: modelPath, skipping: digestFileName)
        let hashFile = modelPath.appendingPathComponent(digestFileName)
        try hash.write(to: hashFile, atomically: true, encoding: .utf8)
        Logger.log("Model modelRepo: \(modelRepo), modelName: \(modelName) hash: \(hash)", log: Logger.general)

        return modelPath
    }

    func getModelPath(modelRepo: String, modelName: String) async throws -> URL {
        if !modelExists(modelRepo: modelRepo, modelName: modelName) {
            let message = "The AI model appears to be broken. Please re-download it from Setup Guide."
            throw NSError(domain: "ModelStorage", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        return getModelDir(modelRepo: modelRepo, modelName: modelName)
    }

    func getModelDir(modelRepo: String, modelName: String) -> URL {
        if modelName != "" {
            return downloader.downloadBase.appendingPathComponent(modelRepo).appendingPathComponent(modelName)
        } else {
            return downloader.downloadBase.appendingPathComponent(modelRepo)
        }
    }

    func deleteModel(modelRepo: String, modelName: String) throws {
        let modelDir = getModelDir(modelRepo: modelRepo, modelName: modelName)

        guard GenericHelper.folderExists(folder: modelDir) else {
            Logger.log("Model modelRepo: \(modelRepo), modelName: \(modelName) does not exist", log: Logger.general)
            return
        }

        do {
            try FileManager.default.removeItem(at: modelDir)
            Logger.log("Successfully deleted model modelRepo: \(modelRepo), modelName: \(modelName) and all its contents", log: Logger.general)
        } catch {
            Logger.log("Failed to delete model modelRepo: \(modelRepo), modelName: \(modelName): \(error.localizedDescription)", log: Logger.general)
            throw error
        }
    }

    func modelExists(modelRepo: String, modelName: String) -> Bool {
        let modelDir = getModelDir(modelRepo: modelRepo, modelName: modelName)
        if !GenericHelper.folderExists(folder: modelDir) {
            return false
        }
        Logger.log("Model modelRepo: \(modelRepo), modelName: \(modelName) already exists at \(modelDir.path)", log: Logger.general)
        do {
            let hashFile = modelDir.appendingPathComponent(digestFileName)
            let hashFileContent = try String(contentsOf: hashFile, encoding: .utf8)

            let hash = try GenericHelper.getDirectoryHash(ofDirectory: modelDir, skipping: digestFileName)
            if hashFileContent != hash {
                Logger.log("Model modelRepo: \(modelRepo), modelName: \(modelName) hash mismatch: hash: \(hash) hashFileContent: \(hashFileContent)", log: Logger.general)
                return false
            }
        } catch {
            Logger.log("Failed to get hash for model modelRepo: \(modelRepo), modelName: \(modelName): \(error.localizedDescription)", log: Logger.general)
            return false
        }
        return true
    }

    func getModelSize(modelRepo: String, modelName: String) -> Int64 {
        let modelDir = getModelDir(modelRepo: modelRepo, modelName: modelName)
        return GenericHelper.folderSize(folder: modelDir)
    }

    func deleteAllModels() {
        // Delete WhisperKit and LLM models
        let modelDir = downloader.downloadBase
        if GenericHelper.folderExists(folder: modelDir) {
            do {
                try FileManager.default.removeItem(at: modelDir)
            } catch {
                Logger.log("Failed to delete all models: \(error.localizedDescription)", log: Logger.general)
            }
        }
        
        // Also delete Parakeet models (stored in FluidAudio's directory)
        do {
            try LocalParakeet.deleteModels()
        } catch {
            Logger.log("Failed to delete Parakeet models: \(error.localizedDescription)", log: Logger.general)
        }
        
        // Delete Diarizer models (for Meeting Notes)
        do {
            try deleteDiarizerModels()
        } catch {
            Logger.log("Failed to delete Diarizer models: \(error.localizedDescription)", log: Logger.general)
        }
    }
    
    // MARK: - Total Storage Accounting
    
    /// Get total size of all downloaded models (including Parakeet and Diarizer)
    func getTotalModelsSize() -> Int64 {
        var totalSize: Int64 = 0
        
        // WhisperKit/LLM models
        let modelDir = downloader.downloadBase
        if GenericHelper.folderExists(folder: modelDir) {
            totalSize += GenericHelper.folderSize(folder: modelDir)
        }
        
        // Parakeet models
        totalSize += LocalParakeet.getModelsSize()
        
        // Diarizer models (for Meeting Notes)
        totalSize += getDiarizerModelsSize()
        
        return totalSize
    }
    
    // MARK: - Parakeet Model Support
    
    func parakeetModelsExist() -> Bool {
        return LocalParakeet.modelsExist()
    }
    
    func parakeetModelsLoaded() -> Bool {
        return LocalParakeet.modelsExist()
    }
    
    func downloadParakeetModels(progress: @escaping (Double) -> Void) async throws {
        try await LocalParakeet.downloadModels(progress: progress)
    }
    
    func deleteParakeetModels() throws {
        try LocalParakeet.deleteModels()
    }
    
    func getParakeetModelsSize() -> Int64 {
        return LocalParakeet.getModelsSize()
    }
    
    // MARK: - Diarizer Model Support (for Meeting Notes)
    
    /// Get the directory where diarizer models are stored by FluidAudio
    func getDiarizerModelsDirectory() -> URL {
        return DiarizerModels.defaultModelsDirectory()
    }
    
    /// Check if diarizer models exist
    func diarizerModelsExist() -> Bool {
        let modelDir = getDiarizerModelsDirectory()
        
        // Check if directory exists and has required model files
        guard FileManager.default.fileExists(atPath: modelDir.path) else {
            return false
        }
        
        // Check for required model files (segmentation and embedding)
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: modelDir, includingPropertiesForKeys: nil)
            let mlmodelcFiles = contents.filter { $0.pathExtension == "mlmodelc" }
            // Need at least 2 models (segmentation + embedding)
            return mlmodelcFiles.count >= 2
        } catch {
            return false
        }
    }
    
    /// Download diarizer models for speaker identification
    func downloadDiarizerModels(progress: @escaping (Double) -> Void) async throws {
        let freeSpace = GenericHelper.getFreeDiskSpace(path: GenericHelper.getAppSupportDirectory())
        if freeSpace < MinimalFreeDiskSpace {
            await WhisperClip.shared?.showNoEnoughDiskSpaceAlert(freeSpace: freeSpace)
            throw NSError(domain: "ModelStorage", code: 2, userInfo: [NSLocalizedDescriptionKey: "Not enough disk space"])
        }
        
        Logger.log("Downloading diarizer models...", log: Logger.general)
        progress(0.1)
        
        // FluidAudio handles its own download and caching
        let _ = try await DiarizerModels.downloadIfNeeded()
        
        progress(1.0)
        Logger.log("Diarizer models downloaded successfully", log: Logger.general)
    }
    
    /// Delete diarizer models
    func deleteDiarizerModels() throws {
        let modelDir = getDiarizerModelsDirectory()
        
        guard FileManager.default.fileExists(atPath: modelDir.path) else {
            return
        }
        
        try FileManager.default.removeItem(at: modelDir)
        Logger.log("Diarizer models deleted", log: Logger.general)
    }
    
    /// Get size of diarizer models
    func getDiarizerModelsSize() -> Int64 {
        let modelDir = getDiarizerModelsDirectory()
        return GenericHelper.folderSize(folder: modelDir)
    }
}
