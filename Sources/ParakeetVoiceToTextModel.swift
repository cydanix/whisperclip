import Foundation
import FluidAudio

class ParakeetVoiceToTextModel: VoiceToTextProtocol {
    static let shared = ParakeetVoiceToTextModel()
    private var manager: AsrManager?

    private init() {
        self.manager = nil
    }

    func load() async throws {
        // Always reload to ensure manager is valid (handles stale cache)
        do {
            self.manager = try await LocalParakeet.loadModel()
        } catch {
            // Clear manager on failure
            self.manager = nil
            throw error
        }

        guard let manager = self.manager, manager.isAvailable else {
            self.manager = nil
            throw NSError(domain: "Transcriber", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to load Parakeet model. Please try again later."])
        }
    }

    func process(filepath: String) async throws -> String {
        try await load()

        guard let manager = self.manager else {
            throw NSError(domain: "Transcriber", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Parakeet manager not available"])
        }

        if GenericHelper.logSensitiveData() {
            Logger.log("Sending transcription query to Parakeet (FluidAudio)", log: Logger.general)
        }
        let ts = TimeSpenter()

        // Transcribe using FluidAudio's URL-based API
        let audioURL = URL(fileURLWithPath: filepath)
        let result = try await manager.transcribe(audioURL)
        let transcription = result.text

        if GenericHelper.logSensitiveData() {
            Logger.log("Received transcription result from Parakeet in \(ts.getDelay()) us", log: Logger.general)
            Logger.log("Parakeet transcription: '\(transcription)'", log: Logger.general)
        }

        if transcription.isEmpty {
            Logger.log("No transcription result received from Parakeet", log: Logger.general, type: .error)
            throw NSError(domain: "Transcriber", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No transcription result received"])
        }

        return transcription
    }
}
