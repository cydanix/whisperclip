import Foundation
import FluidAudio

class LocalParakeet {
    private static var cachedManager: AsrManager?
    
    /// Get the directory where Parakeet models are stored
    static func getModelsDirectory() -> URL {
        return AsrModels.defaultCacheDirectory(for: .v3)
    }
    
    /// Check if Parakeet models are downloaded
    static func modelsExist() -> Bool {
        return AsrModels.modelsExist(at: getModelsDirectory(), version: .v3)
    }
    
    /// Get the size of downloaded Parakeet models
    static func getModelsSize() -> Int64 {
        let directory = getModelsDirectory()
        return GenericHelper.folderSize(folder: directory)
    }
    
    /// Delete downloaded Parakeet models
    static func deleteModels() throws {
        let directory = getModelsDirectory()
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
            Logger.log("Parakeet models deleted from \(directory.path)", log: Logger.general)
        }
        cachedManager = nil
    }
    
    /// Download Parakeet models with progress tracking
    /// Progress milestones: download=0-70%, load=70-90%, initialize=90-100%
    static func downloadModels(progress: @escaping (Double) -> Void) async throws {
        Logger.log("Downloading Parakeet models...", log: Logger.general)
        
        // Check if models already exist
        if modelsExist() {
            Logger.log("Parakeet models already exist, skipping download", log: Logger.general)
            progress(1.0)
            return
        }
        
        // Check disk space first
        let freeSpace = GenericHelper.getFreeDiskSpace(path: GenericHelper.getAppSupportDirectory())
        if freeSpace < MinimalFreeDiskSpace {
            let shouldContinue = await WhisperClip.shared?.showNoEnoughDiskSpaceAlert(freeSpace: freeSpace) ?? false
            if !shouldContinue {
                throw NSError(domain: "LocalParakeet", code: 2, 
                              userInfo: [NSLocalizedDescriptionKey: "Not enough disk space. Required: 20GB, Available: \(GenericHelper.formatSize(size: freeSpace))"])
            }
        }
        
        // Clear any stale cache before downloading
        clearCache()
        
        progress(0.01)
        
        do {
            // Download models - FluidAudio handles the download internally
            // No granular progress available, milestone at 70%
            _ = try await AsrModels.download(version: .v3)
            progress(0.70)
            
            // Load models to trigger CoreML compilation
            let models = try await AsrModels.load(from: getModelsDirectory(), version: .v3)
            progress(0.90)
            
            // Initialize the manager to verify everything works
            let manager = AsrManager(config: .default)
            try await manager.initialize(models: models)
            
            // Verify manager is actually available
            guard manager.isAvailable else {
                throw NSError(domain: "LocalParakeet", code: 3,
                              userInfo: [NSLocalizedDescriptionKey: "Parakeet manager initialized but not available"])
            }
            
            cachedManager = manager
            
            progress(1.0)
            Logger.log("Parakeet models downloaded and loaded successfully", log: Logger.general)
        } catch {
            Logger.log("Failed to download Parakeet models: \(error)", log: Logger.general, type: .error)
            // Clean up on failure
            clearCache()
            try? deleteModels()
            throw error
        }
    }
    
    /// Load Parakeet model (downloads if needed)
    static func loadModel() async throws -> AsrManager {
        // Validate models exist first
        guard modelsExist() else {
            throw NSError(domain: "LocalParakeet", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Parakeet models not downloaded. Please download them from Setup Guide."])
        }
        
        // Return cached manager if available and valid
        if let manager = cachedManager, manager.isAvailable {
            return manager
        }
        
        Logger.log("Loading Parakeet model via FluidAudio", log: Logger.general)

        // Load models (they should already exist at this point)
        let models = try await AsrModels.load(from: getModelsDirectory(), version: .v3)

        // Create and initialize ASR manager
        let config = ASRConfig.default
        let manager = AsrManager(config: config)
        try await manager.initialize(models: models)
        
        // Verify manager is actually available
        guard manager.isAvailable else {
            clearCache()
            throw NSError(domain: "LocalParakeet", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Parakeet manager initialized but not available"])
        }
        
        cachedManager = manager

        Logger.log("Parakeet model loaded successfully", log: Logger.general)
        return manager
    }
    
    /// Clear cached manager (useful when deleting models)
    static func clearCache() {
        cachedManager = nil
    }
}
