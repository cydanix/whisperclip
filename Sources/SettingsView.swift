import SwiftUI
import Cocoa

struct SettingsView: View {
    @StateObject private var settings = SettingsStore.shared
    @State private var selectedLanguage: String = "auto"
    @State private var selectedModifierRawValue: UInt = NSEvent.ModifierFlags.command.rawValue
    @State private var hotkeyKeyString: String = "Space"
    @State private var selectedKeyCode: UInt16 = 49 // Default to Space
    
    // Prompt management state
    @State private var showingNewPromptDialog = false
    @State private var newPromptLabel = ""
    @State private var newPromptContent = ""
    @State private var editingPromptId: String? = nil
    @State private var editingPromptLabel = ""
    @State private var editingPromptContent = ""
    
    // Reset confirmation state
    @State private var showingResetConfirmation = false
    
    // Delete models confirmation state
    @State private var showingDeleteModelsConfirmation = false
    
    // Language options
    private let languageOptions = [
        ("auto", "Auto Detect"),
        ("en", "English"),
        ("es", "Spanish"),
        ("fr", "French"),
        ("de", "German"),
        ("it", "Italian"),
        ("pt", "Portuguese"),
        ("ru", "Russian"),
        ("ja", "Japanese"),
        ("ko", "Korean"),
        ("zh", "Chinese"),
        ("ar", "Arabic"),
        ("hi", "Hindi"),
        ("tr", "Turkish"),
        ("pl", "Polish"),
        ("nl", "Dutch"),
        ("sv", "Swedish"),
        ("da", "Danish"),
        ("no", "Norwegian"),
        ("fi", "Finnish")
    ]
    
    // Modifier key options using raw values
    private let modifierOptions: [(UInt, String)] = [
        (NSEvent.ModifierFlags.command.rawValue, "⌘ Command"),
        (NSEvent.ModifierFlags.option.rawValue, "⌥ Option"),
        (NSEvent.ModifierFlags.control.rawValue, "⌃ Control"),
        (NSEvent.ModifierFlags.shift.rawValue, "⇧ Shift"),
        (NSEvent.ModifierFlags([.command, .option]).rawValue, "⌘⌥ Command+Option"),
        (NSEvent.ModifierFlags([.command, .control]).rawValue, "⌘⌃ Command+Control"),
        (NSEvent.ModifierFlags([.command, .shift]).rawValue, "⌘⇧ Command+Shift"),
        (NSEvent.ModifierFlags([.option, .control]).rawValue, "⌥⌃ Option+Control"),
        (NSEvent.ModifierFlags([.option, .shift]).rawValue, "⌥⇧ Option+Shift"),
        (NSEvent.ModifierFlags([.control, .shift]).rawValue, "⌃⇧ Control+Shift")
    ]
    
    // Allowed key options (safe keys that won't interfere with system hotkeys)
    private let keyOptions: [(UInt16, String)] = [
        (49, "Space"),
        (36, "Return"),
        (48, "Tab"),
        (51, "Delete"),
        (53, "Escape"),
        (96, "F5"),
        (97, "F6"),
        (98, "F7"),
        (100, "F8"),
        (101, "F9"),
        (109, "F10"),
        (103, "F11"),
        (111, "F12"),
        (105, "F13"),
        (107, "F14"),
        (113, "F15")
    ]
    
    var body: some View {
        TabView {
            // General Settings Tab
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Transcription Language")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            Picker("Language", selection: $selectedLanguage) {
                                ForEach(languageOptions, id: \.0) { option in
                                    Text(option.1).tag(option.0)
                                }
                            }
                            .pickerStyle(.menu)
                            .onChange(of: selectedLanguage) { _, newValue in
                                settings.language = newValue
                            }
                            
                            Text("Select the language for speech recognition. Auto Detect will try to identify the language automatically.")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .padding()
                    }
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
                    
                     GroupBox {
                         VStack(alignment: .leading, spacing: 12) {
                             Text("Auto Actions")
                                 .font(.headline)
                                 .foregroundColor(.white)
                             
                             Toggle("Auto-press Enter after paste", isOn: Binding(
                                 get: { settings.autoEnter },
                                 set: { newValue in
                                     settings.autoEnter = newValue
                                 }
                             ))
                             
                             Text("Automatically press Enter after pasting transcribed text into the active application.")
                                 .font(.caption)
                                 .foregroundColor(.gray)
                         }
                         .padding()
                     }
                     .background(Color.gray.opacity(0.2))
                     .cornerRadius(8)
                     
                     GroupBox {
                         VStack(alignment: .leading, spacing: 12) {
                             Text("Startup Behavior")
                                 .font(.headline)
                                 .foregroundColor(.white)
                             
                             Toggle("Start minimized", isOn: Binding(
                                 get: { settings.startMinimized },
                                 set: { newValue in
                                     settings.startMinimized = newValue
                                 }
                             ))
                             
                             Text("Start the application minimized to the Dock.")
                                 .font(.caption)
                                 .foregroundColor(.gray)
                         }
                         .padding()
                     }
                     .background(Color.gray.opacity(0.2))
                     .cornerRadius(8)
                    
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Storage Management")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            Text("Delete all downloaded AI models from your system. This will free up disk space but you'll need to re-download models when needed. Downloaded models are typically stored in your Application Support directory.")
                                .font(.body)
                                .foregroundColor(.gray)
                            
                            HStack {
                                Button("Delete All Models") {
                                    showingDeleteModelsConfirmation = true
                                }
                                .buttonStyle(.bordered)
                                .foregroundColor(.red)
                                
                                Spacer()
                            }
                        }
                        .padding()
                    }
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
                    
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Reset to Defaults")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            Text("This will reset all settings to their default values, including language, hotkeys, and prompts. This action cannot be undone.")
                                .font(.body)
                                .foregroundColor(.gray)
                            
                            HStack {
                                Button("Reset All Settings") {
                                    showingResetConfirmation = true
                                }
                                .buttonStyle(.bordered)
                                .foregroundColor(.red)
                                
                                Spacer()
                            }
                        }
                        .padding()
                    }
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
                }
                .padding()
            }
            .background(Color.black)
            .tabItem {
                Label("General", systemImage: "gear")
            }
            
            // Hot Key Settings Tab
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 16) {
                            Toggle("Enable Global Hotkey", isOn: Binding(
                                get: { settings.hotkeyEnabled },
                                set: { newValue in
                                    settings.hotkeyEnabled = newValue
                                    updateHotkey()
                                }
                            ))
                            .font(.headline)
                            
                            if settings.hotkeyEnabled {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Modifier Keys")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.white)
                                    
                                    Picker("Modifier", selection: $selectedModifierRawValue) {
                                        ForEach(modifierOptions, id: \.0) { option in
                                            Text(option.1).tag(option.0)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .onChange(of: selectedModifierRawValue) { _, newValue in
                                        let modifierFlags = NSEvent.ModifierFlags(rawValue: newValue)
                                        settings.hotkeyModifier = modifierFlags
                                        updateHotkey()
                                    }
                                    
                                    Text("Key")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.white)
                                    
                                    Picker("Key", selection: $selectedKeyCode) {
                                        ForEach(keyOptions, id: \.0) { option in
                                            Text(option.1).tag(option.0)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .onChange(of: selectedKeyCode) { _, newValue in
                                        settings.hotkeyKey = newValue
                                        hotkeyKeyString = keyCodeToString(newValue)
                                        updateHotkey()
                                    }
                                    
                                    Text("Current hotkey: \(getModifierString()) + \(hotkeyKeyString)")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            }
                            
                            Text("Use the global hotkey to start/stop recording from anywhere on your system.")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .padding()
                    }
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
                }
                .padding()
            }
            .background(Color.black)
            .tabItem {
                Label("Hot Key", systemImage: "keyboard")
            }
            
            // Prompt Settings Tab
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 16) {
                            // Header with Create button
                            HStack {
                                Text("Enhancement Prompts")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                
                                Spacer()
                                
                                Button("New Prompt") {
                                    showingNewPromptDialog = true
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            
                            if settings.prompts.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "text.bubble")
                                        .font(.system(size: 48))
                                        .foregroundColor(.gray)
                                    
                                    Text("No prompts created yet")
                                        .font(.title2)
                                        .fontWeight(.medium)
                                        .foregroundColor(.white)
                                    
                                    Text("Create prompts to enhance or modify transcribed text with AI")
                                        .font(.body)
                                        .foregroundColor(.gray)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 32)
                            } else {
                                // Selected prompt indicator
                                if let selectedId = settings.selectedPromptId,
                                   let selectedPrompt = settings.prompts.first(where: { $0.id == selectedId }) {
                                    HStack {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                        Text("Active: \(selectedPrompt.label)")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.green.opacity(0.1))
                                    .cornerRadius(8)
                                }
                                
                                // Prompts list
                                LazyVStack(spacing: 8) {
                                    ForEach(settings.prompts) { prompt in
                                        PromptRowView(
                                            prompt: prompt,
                                            isSelected: settings.selectedPromptId == prompt.id,
                                            isEditing: editingPromptId == prompt.id,
                                            editingLabel: $editingPromptLabel,
                                            editingContent: $editingPromptContent,
                                            onSelect: { settings.selectPrompt(id: prompt.id) },
                                            onEdit: { startEditing(prompt) },
                                            onSave: { savePromptEdits(prompt.id) },
                                            onCancel: { cancelEditing() },
                                            onDelete: { settings.deletePrompt(id: prompt.id) }
                                        )
                                    }
                                }
                            }
                            
                            Text("Create and manage prompts to enhance transcribed text with AI. Select one to make it active.")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .padding()
                    }
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
                }
                .padding()
            }
            .background(Color.black)
            .tabItem {
                Label("Prompts", systemImage: "text.bubble")
            }
        }
        .sheet(isPresented: $showingNewPromptDialog) {
            NewPromptDialog(
                label: $newPromptLabel,
                content: $newPromptContent,
                onCreate: { createNewPrompt() },
                onCancel: { cancelNewPrompt() }
            )
        }
        .alert("Reset Settings", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                resetSettings()
            }
        } message: {
            Text("Are you sure you want to reset all settings to their default values? This will reset language preferences, hotkeys, and all prompts. This action cannot be undone.")
        }
        .alert("Delete All Models", isPresented: $showingDeleteModelsConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete All", role: .destructive) {
                deleteAllModels()
            }
        } message: {
            Text("Are you sure you want to delete all downloaded AI models? This will free up disk space but you'll need to re-download models when they're needed again. This action cannot be undone.")
        }
        .frame(minWidth: 500, minHeight: 400)
        .background(Color.black)
        .preferredColorScheme(.dark)
        .onAppear {
            loadCurrentSettings()
        }
        .onChange(of: settings.language) { _, newValue in
            selectedLanguage = newValue
        }
        .onChange(of: settings.hotkeyModifier) { _, newValue in
            selectedModifierRawValue = newValue.rawValue
        }
        .onChange(of: settings.hotkeyKey) { _, newValue in
            selectedKeyCode = newValue
            hotkeyKeyString = keyCodeToString(newValue)
        }
    }
    
    private func loadCurrentSettings() {
        selectedLanguage = settings.language
        selectedModifierRawValue = settings.hotkeyModifier.rawValue
        selectedKeyCode = settings.hotkeyKey
        hotkeyKeyString = keyCodeToString(settings.hotkeyKey)
    }
    
    private func updateHotkey() {
        // Update the hotkey manager with new settings
        HotkeyManager.shared.updateSystemHotkey(
            hotkeyEnabled: settings.hotkeyEnabled,
            modifier: settings.hotkeyModifier,
            keyCode: settings.hotkeyKey
        )
    }
    
    private func getModifierString() -> String {
        let modifierRawValue = settings.hotkeyModifier.rawValue
        for option in modifierOptions {
            if option.0 == modifierRawValue {
                return option.1
            }
        }
        return "⌘ Command" // Default fallback
    }
    
    private func keyCodeToString(_ keyCode: UInt16) -> String {
        // Map key codes to their string representations
        for option in keyOptions {
            if option.0 == keyCode {
                return option.1
            }
        }
        return "Key \(keyCode)" // Fallback for unknown keys
    }
    
    // MARK: - Prompt Management
    
    private func createNewPrompt() {
        guard !newPromptLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        _ = settings.createPrompt(label: newPromptLabel, content: newPromptContent)
        
        // Reset form
        newPromptLabel = ""
        newPromptContent = ""
        showingNewPromptDialog = false
    }
    
    private func cancelNewPrompt() {
        newPromptLabel = ""
        newPromptContent = ""
        showingNewPromptDialog = false
    }
    
    private func startEditing(_ prompt: Prompt) {
        editingPromptId = prompt.id
        editingPromptLabel = prompt.label
        editingPromptContent = prompt.content
    }
    
    private func savePromptEdits(_ promptId: String) {
        settings.updatePrompt(
            id: promptId,
            label: editingPromptLabel,
            content: editingPromptContent
        )
        cancelEditing()
    }
    
    private func cancelEditing() {
        editingPromptId = nil
        editingPromptLabel = ""
        editingPromptContent = ""
    }
    
    // MARK: - Reset Settings
    
    private func resetSettings() {
        settings.resetToDefaults()
        loadCurrentSettings()
        updateHotkey()
    }
    
    // MARK: - Model Management
    
    private func deleteAllModels() {
        ModelStorage.shared.deleteAllModels()
        Logger.log("All models deleted by user", log: Logger.general)
    }
}

// MARK: - Prompt Row View

struct PromptRowView: View {
    let prompt: Prompt
    let isSelected: Bool
    let isEditing: Bool
    @Binding var editingLabel: String
    @Binding var editingContent: String
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onSave: () -> Void
    let onCancel: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isEditing {
                // Editing mode
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Prompt name", text: $editingLabel)
                        .textFieldStyle(.roundedBorder)
                    
                    TextEditor(text: $editingContent)
                        .frame(minHeight: 80)
                        .padding(8)
                        .background(Color.gray.opacity(0.3))
                        .cornerRadius(6)
                    
                    HStack {
                        Button("Cancel") {
                            onCancel()
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Save") {
                            onSave()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(editingLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            } else {
                // Display mode
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(prompt.label)
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                            }
                        }
                        
                        if !prompt.content.isEmpty {
                            Text(prompt.content)
                                .font(.caption)
                                .foregroundColor(.gray)
                                .lineLimit(3)
                        } else {
                            Text("Empty prompt")
                                .font(.caption)
                                .foregroundColor(.gray)
                                .italic()
                        }
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 8) {
                        if !isSelected {
                            Button("Select") {
                                onSelect()
                            }
                            .buttonStyle(.bordered)
                        }
                        
                        Button("Edit") {
                            onEdit()
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Delete") {
                            onDelete()
                        }
                        .buttonStyle(.bordered)
                        .foregroundColor(.red)
                    }
                }
            }
        }
        .padding()
        .background(isSelected ? Color.blue.opacity(0.3) : Color.gray.opacity(0.3))
        .cornerRadius(8)
    }
}

// MARK: - New Prompt Dialog

struct NewPromptDialog: View {
    @Binding var label: String
    @Binding var content: String
    let onCreate: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create New Prompt")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Prompt Name")
                    .font(.headline)
                    .foregroundColor(.white)
                TextField("Enter prompt name", text: $label)
                    .textFieldStyle(.roundedBorder)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Prompt Content")
                    .font(.headline)
                    .foregroundColor(.white)
                TextEditor(text: $content)
                    .frame(minHeight: 120)
                    .padding(8)
                    .background(Color.gray.opacity(0.3))
                    .cornerRadius(6)
                
                Text("Optional: Provide instructions to enhance or modify transcribed text with AI.")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Create") {
                    onCreate()
                }
                .buttonStyle(.borderedProminent)
                .disabled(label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 450, height: 350)
        .background(Color.black)
        .preferredColorScheme(.dark)
    }
}
