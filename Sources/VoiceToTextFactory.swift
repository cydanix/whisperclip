import Foundation

@MainActor
class VoiceToTextFactory {
    static func createVoiceToText() -> VoiceToTextProtocol {
        let settings = SettingsStore.shared
        switch settings.sttEngine {
        case .whisperKit:
            return VoiceToTextModel.shared
        case .parakeet:
            return ParakeetVoiceToTextModel.shared
        }
    }
}
