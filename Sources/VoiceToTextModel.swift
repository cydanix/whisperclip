import Foundation
import WhisperKit

class VoiceToTextModel: VoiceToTextProtocol {
    static let shared = VoiceToTextModel()
    private var pipe: WhisperKit?

    private init() {
        self.pipe = nil
    }

    func load() async throws {

        if self.pipe == nil {
            self.pipe = try await LocalWhisperKit.loadModel(modelRepo: CurrentSTTModelRepo, modelName: CurrentSTTModelName)
        }

        if self.pipe == nil {
            throw NSError(domain: "Transcriber", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to load voice-to-text model. Please try again later."])
        }
    }

    func process(filepath: String) async throws -> String {
        try await load()

        let language = SettingsStore.shared.language
        let languageCode = language == "auto" ? nil : language

        if GenericHelper.logSensitiveData() {
            Logger.log("Sending transcription query to WhisperKit with lang: \(languageCode ?? "auto")", log: Logger.general)
        }
        let ts = TimeSpenter()

        let results = try await pipe!.transcribe(
            audioPath: filepath,
            decodeOptions: DecodingOptions(
                language: languageCode,
                usePrefillPrompt: true,
                detectLanguage: language == "auto"
            )
        )
        let transcription = results.first?.text
        if GenericHelper.logSensitiveData() {
            Logger.log("Received transcription result from WhisperKit in \(ts.getDelay()) us", log: Logger.general)
        }

        if transcription == nil {
            Logger.log("No transcription result received", log: Logger.general, type: .error)

            throw NSError(domain: "Transcriber", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No transcription result received"])
        }

        return transcription!
    }
}
