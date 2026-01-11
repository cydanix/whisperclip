import Cocoa
import SwiftUI
import Foundation

struct Prompt: Codable, Identifiable {
    let id: String
    var label: String
    var content: String
    
    init(label: String, content: String) {
        self.id = UUID().uuidString
        self.label = label
        self.content = content
    }
}

struct DefaultSettings {
    static let hasCompletedOnboarding = false
    static let language = "auto"
    static let autoEnter = false
    static let startMinimized = false
    static let displayRecordingOverlay = false
    static let overlayPosition = "topRight"
    static let hotkeyEnabled = true
    static let hotkeyModifier = NSEvent.ModifierFlags.option
    static let hotkeyKey: UInt16 = 49 // Space key
    static let holdToTalk = false
    static let prompts: [Prompt] = [
        Prompt(label: "None", content: ""),
        Prompt(label: "Translate to English", content: "Translate the following text to English:"),
        Prompt(label: "Grammar Fix & Email", content: "Fix the grammar and format this as a professional email:")
    ]
    static var selectedPromptId: String? { prompts.first?.id }
}

class SettingsStore: ObservableObject {
    static let shared = SettingsStore()
    // UserDefaults keys
    private enum Keys: String {
        case hasCompletedOnboarding = "hasCompletedOnboarding"
        case language = "language"
        case autoEnter = "autoEnter"
        case startMinimized = "startMinimized"
        case displayRecordingOverlay = "displayRecordingOverlay"
        case overlayPosition = "overlayPosition"
        case hotkeyEnabled = "hotkeyEnabled"
        case hotkeyModifier = "hotkeyModifier"
        case hotkeyKey = "hotkeyKey"
        case holdToTalk = "holdToTalk"
        case prompts = "prompts"
        case selectedPromptId = "selectedPromptId"
    }

    private let defaults = UserDefaults.standard

    @Published var hasCompletedOnboarding: Bool = false {
        didSet {
            defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding.rawValue)
        }
    }
    
    @Published var language: String = "auto" {
        didSet {
            defaults.set(language, forKey: Keys.language.rawValue)
        }
    }
    
    @Published var autoEnter: Bool = DefaultSettings.autoEnter {
        didSet {
            defaults.set(autoEnter, forKey: Keys.autoEnter.rawValue)
        }
    }
    
    @Published var startMinimized: Bool = DefaultSettings.startMinimized {
        didSet {
            defaults.set(startMinimized, forKey: Keys.startMinimized.rawValue)
        }
    }

    @Published var displayRecordingOverlay: Bool = DefaultSettings.displayRecordingOverlay {
        didSet {
            defaults.set(displayRecordingOverlay, forKey: Keys.displayRecordingOverlay.rawValue)
        }
    }

    @Published var overlayPosition: String = DefaultSettings.overlayPosition {
        didSet {
            defaults.set(overlayPosition, forKey: Keys.overlayPosition.rawValue)
        }
    }

    @Published var hotkeyEnabled: Bool = true {
        didSet {
            defaults.set(hotkeyEnabled, forKey: Keys.hotkeyEnabled.rawValue)
        }
    }
    
    @Published var hotkeyModifier: NSEvent.ModifierFlags = DefaultSettings.hotkeyModifier {
        didSet {
            defaults.set(hotkeyModifier.rawValue, forKey: Keys.hotkeyModifier.rawValue)
        }
    }
    
    @Published var hotkeyKey: UInt16 = DefaultSettings.hotkeyKey {
        didSet {
            defaults.set(hotkeyKey, forKey: Keys.hotkeyKey.rawValue)
        }
    }

    @Published var holdToTalk: Bool = DefaultSettings.holdToTalk {
        didSet {
            defaults.set(holdToTalk, forKey: Keys.holdToTalk.rawValue)
        }
    }

    @Published var prompts: [Prompt] = [] {
        didSet {
            savePrompts()
        }
    }
    
    @Published var selectedPromptId: String? = nil {
        didSet {
            defaults.set(selectedPromptId, forKey: Keys.selectedPromptId.rawValue)
        }
    }
    
    // Computed property to get the current prompt content
    var currentPrompt: String {
        guard let selectedId = selectedPromptId,
              let prompt = prompts.first(where: { $0.id == selectedId }) else {
            return ""
        }
        return prompt.content
    }

    private init() {
        loadSettings()
    }
    
    private func loadSettings() {
        // Load values from UserDefaults with default values
        // Note: Property observers are temporarily disabled during init
        self.hasCompletedOnboarding = defaults.object(forKey: Keys.hasCompletedOnboarding.rawValue) == nil ? DefaultSettings.hasCompletedOnboarding : defaults.bool(forKey: Keys.hasCompletedOnboarding.rawValue)
        self.language = defaults.string(forKey: Keys.language.rawValue) ?? DefaultSettings.language
        self.autoEnter = defaults.object(forKey: Keys.autoEnter.rawValue) == nil ? DefaultSettings.autoEnter : defaults.bool(forKey: Keys.autoEnter.rawValue)
        self.startMinimized = defaults.object(forKey: Keys.startMinimized.rawValue) == nil ? DefaultSettings.startMinimized : defaults.bool(forKey: Keys.startMinimized.rawValue)
        self.displayRecordingOverlay = defaults.object(forKey: Keys.displayRecordingOverlay.rawValue) == nil ? DefaultSettings.displayRecordingOverlay : defaults.bool(forKey: Keys.displayRecordingOverlay.rawValue)
        self.overlayPosition = defaults.string(forKey: Keys.overlayPosition.rawValue) ?? DefaultSettings.overlayPosition
        self.hotkeyEnabled = defaults.object(forKey: Keys.hotkeyEnabled.rawValue) == nil ? DefaultSettings.hotkeyEnabled : defaults.bool(forKey: Keys.hotkeyEnabled.rawValue)
        self.hotkeyModifier = NSEvent.ModifierFlags(rawValue: defaults.object(forKey: Keys.hotkeyModifier.rawValue) as? UInt ?? DefaultSettings.hotkeyModifier.rawValue)
        self.hotkeyKey = defaults.object(forKey: Keys.hotkeyKey.rawValue) == nil ? DefaultSettings.hotkeyKey : UInt16(defaults.integer(forKey: Keys.hotkeyKey.rawValue))
        self.holdToTalk = defaults.object(forKey: Keys.holdToTalk.rawValue) == nil ? DefaultSettings.holdToTalk : defaults.bool(forKey: Keys.holdToTalk.rawValue)
        self.selectedPromptId = defaults.string(forKey: Keys.selectedPromptId.rawValue) ?? DefaultSettings.selectedPromptId
        
        // Load prompts
        if let promptsData = defaults.data(forKey: Keys.prompts.rawValue),
           let decodedPrompts = try? JSONDecoder().decode([Prompt].self, from: promptsData) {
            self.prompts = decodedPrompts
        } else {
            self.prompts = DefaultSettings.prompts
        }
    }
    
    private func savePrompts() {
        if let encoded = try? JSONEncoder().encode(prompts) {
            defaults.set(encoded, forKey: Keys.prompts.rawValue)
        }
    }
    
    // MARK: - Prompt Management
    
    func createPrompt(label: String, content: String = "") -> Prompt {
        let newPrompt = Prompt(label: label, content: content)
        prompts.append(newPrompt)
        
        // If this is the first prompt or no prompt is selected, select this one
        if selectedPromptId == nil || prompts.count == 1 {
            selectedPromptId = newPrompt.id
        }
        
        return newPrompt
    }
    
    func updatePrompt(id: String, label: String? = nil, content: String? = nil) {
        guard let index = prompts.firstIndex(where: { $0.id == id }) else { return }
        
        if let label = label {
            prompts[index].label = label
        }
        if let content = content {
            prompts[index].content = content
        }
    }
    
    func deletePrompt(id: String) {
        prompts.removeAll { $0.id == id }
        
        // If the deleted prompt was selected, select the first available prompt or nil
        if selectedPromptId == id {
            selectedPromptId = prompts.first?.id
        }
    }
    
    func selectPrompt(id: String) {
        if prompts.contains(where: { $0.id == id }) {
            selectedPromptId = id
        }
    }
    
    // MARK: - Reset Settings
    
    func resetToDefaults() {
        // Update published properties directly (synchronously)
        // This will trigger didSet observers which will update UserDefaults
        hasCompletedOnboarding = DefaultSettings.hasCompletedOnboarding
        language = DefaultSettings.language
        autoEnter = DefaultSettings.autoEnter
        startMinimized = DefaultSettings.startMinimized
        displayRecordingOverlay = DefaultSettings.displayRecordingOverlay
        overlayPosition = DefaultSettings.overlayPosition
        hotkeyEnabled = DefaultSettings.hotkeyEnabled
        hotkeyModifier = DefaultSettings.hotkeyModifier
        hotkeyKey = DefaultSettings.hotkeyKey
        holdToTalk = DefaultSettings.holdToTalk
        prompts = DefaultSettings.prompts
        selectedPromptId = DefaultSettings.selectedPromptId
    }

}