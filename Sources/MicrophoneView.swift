import SwiftUI
import AVFoundation
import AppKit

struct MicrophoneView: View {
    @ObservedObject private var audio = AudioRecorder.shared
    @State private var resultText: String = ""
    @State private var isProcessing: Bool = false
    @State private var isTranscribing: Bool = false
    @State private var showShareSheet: Bool = false
    @State private var statusMessage: String = ""
    @State private var errorMessage: String = ""
    @State private var startedByHotkey = false
    @State private var overlayShown = false
    @State private var showDonationDialog = false
    @State private var pulseAnimation = false

    @StateObject private var hotkeyManager = HotkeyManager.shared
    @StateObject private var settings = SettingsStore.shared
    @State private var recordingTimer: Timer? = nil
    
    private var statusText: String {
        if audio.isRecording {
            return "Recording..."
        } else if isProcessing {
            return "Processing..."
        } else {
            return "Ready"
        }
    }
    
    private var hotkeyHint: String {
        guard settings.hotkeyEnabled else { return "" }
        
        var parts: [String] = []
        let modifier = settings.hotkeyModifier
        if modifier.contains(.control) { parts.append("⌃") }
        if modifier.contains(.option) { parts.append("⌥") }
        if modifier.contains(.shift) { parts.append("⇧") }
        if modifier.contains(.command) { parts.append("⌘") }
        
        let keyName: String
        switch settings.hotkeyKey {
        case 49: keyName = "Space"
        case 36: keyName = "Return"
        case 48: keyName = "Tab"
        case 51: keyName = "Delete"
        case 53: keyName = "Escape"
        default: keyName = "Key"
        }
        parts.append(keyName)
        
        return parts.joined(separator: " ")
    }
    
    private var statusSubtext: String {
        if audio.isRecording {
            return "Speak now • Press hotkey or button to stop"
        } else if isProcessing {
            return "Transcribing your audio..."
        } else {
            let hint = hotkeyHint.isEmpty ? "" : " or use \(hotkeyHint)"
            return "Press the button\(hint) to start"
        }
    }

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.08),
                    Color(red: 0.08, green: 0.06, blue: 0.12),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                Spacer()
                
                // Main content area
                VStack(spacing: 24) {
                    // Microphone visualization
                    ZStack {
                        // Outer pulse rings (when recording)
                        if audio.isRecording {
                            ForEach(0..<3, id: \.self) { i in
                                Circle()
                                    .stroke(Color.red.opacity(0.3 - Double(i) * 0.1), lineWidth: 2)
                                    .frame(width: 160 + CGFloat(i) * 40, height: 160 + CGFloat(i) * 40)
                                    .scaleEffect(pulseAnimation ? 1.1 : 1.0)
                                    .opacity(pulseAnimation ? 0.0 : 0.6)
                                    .animation(
                                        .easeInOut(duration: 1.5)
                                        .repeatForever(autoreverses: false)
                                        .delay(Double(i) * 0.3),
                                        value: pulseAnimation
                                    )
                            }
                        }
                        
                        // Glow effect
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        audio.isRecording ? Color.red.opacity(0.3) : Color.orange.opacity(0.15),
                                        Color.clear
                                    ],
                                    center: .center,
                                    startRadius: 40,
                                    endRadius: 100
                                )
                            )
                            .frame(width: 200, height: 200)
                            .blur(radius: 20)
                        
                        // Main circle background
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: audio.isRecording 
                                        ? [Color.red.opacity(0.8), Color.red.opacity(0.6)]
                                        : [Color.white.opacity(0.1), Color.white.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 140, height: 140)
                            .overlay(
                                Circle()
                                    .stroke(
                                        audio.isRecording ? Color.red : Color.white.opacity(0.2),
                                        lineWidth: 2
                                    )
                            )
                            .shadow(color: audio.isRecording ? Color.red.opacity(0.5) : Color.clear, radius: 20)
                        
                        // Mic icon or waveform
                        if audio.isRecording {
                            WaveformView(audio: audio)
                                .frame(width: 110, height: 110)
                        } else if isProcessing {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(1.5)
                                .tint(.orange)
                        } else {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 50, weight: .light))
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                    .frame(height: 220)
                    
                    // Status text
                    VStack(spacing: 8) {
                        Text(statusText)
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                        
                        Text(statusSubtext)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.gray)
                    }
                    
                    // Record button
                    Button {
                        toggleRecording()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: audio.isRecording ? "stop.fill" : "circle.fill")
                                .font(.system(size: 16))
                            Text(audio.isRecording ? "Stop Recording" : "Start Recording")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 16)
                        .background(
                            Capsule()
                                .fill(audio.isRecording 
                                    ? LinearGradient(colors: [.red, .red.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
                                    : LinearGradient(colors: [.orange, .orange.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
                                )
                        )
                        .shadow(color: audio.isRecording ? .red.opacity(0.4) : .orange.opacity(0.4), radius: 10, y: 5)
                    }
                    .buttonStyle(.plain)
                    .disabled(isProcessing && !audio.isRecording)
                    .opacity(isProcessing && !audio.isRecording ? 0.5 : 1.0)
                }
                
                Spacer()
                
                // Results section
                if !resultText.isEmpty || !errorMessage.isEmpty {
                    VStack(spacing: 0) {
                        Divider()
                            .background(Color.white.opacity(0.1))
                        
                        if !resultText.isEmpty {
                            ResultView(resultText: resultText, statusMessage: statusMessage, showShareSheet: $showShareSheet)
                                .padding(20)
                        }
                        
                        if !errorMessage.isEmpty {
                            ErrorView(errorMessage: errorMessage)
                                .padding(20)
                        }
                    }
                    .background(Color.black.opacity(0.3))
                }
            }
        }
        .foregroundColor(.white)
        .onChange(of: audio.isRecording) { _, isRecording in
            if isRecording {
                pulseAnimation = true
            } else {
                pulseAnimation = false
            }
        }
        .onAppear {
            Logger.log("MicrophoneView appeared", log: Logger.general)
            hotkeyManager.setAction(action: {
                Logger.log("Hotkey action triggered (keyDown)", log: Logger.hotkey)
                if settings.holdToTalk {
                    if !audio.isRecording && !isProcessing {
                        self.startedByHotkey = true
                        self.startRecording()
                    }
                } else {
                    self.startedByHotkey = true
                    self.toggleRecording()
                }
            })
            hotkeyManager.setKeyUpAction(action: {
                Logger.log("Hotkey action triggered (keyUp)", log: Logger.hotkey)
                if settings.holdToTalk {
                    if audio.isRecording {
                        self.stopRecording()
                    }
                }
            })
            hotkeyManager.updateSystemHotkey(
                hotkeyEnabled: settings.hotkeyEnabled,
                modifier: settings.hotkeyModifier,
                keyCode: settings.hotkeyKey
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .recordingStarted)) { _ in
            if startedByHotkey && settings.displayRecordingOverlay {
                RecordingOverlayManager.shared.show()
                overlayShown = true
            }
            startedByHotkey = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .didFinishRecording)) { notif in
            if overlayShown {
                RecordingOverlayManager.shared.hide()
                overlayShown = false
            }

            if let fileUrl = notif.object as? URL {
                if !GenericHelper.fileExists(file: fileUrl) {
                    Logger.log("Recording file \(fileUrl.path) not found", log: Logger.audio, type: .error)
                    resetState(error: "Recording file not found. Please try again.")
                    return
                }

                transcribeAudio(url: fileUrl, source: .microphone)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .recordingError)) { notif in
            if overlayShown {
                RecordingOverlayManager.shared.hide()
                overlayShown = false
            }

            if let error = notif.object as? String {
                Logger.log("Recording error: \(error)", log: Logger.audio, type: .error)
                resetState(error: "Recording failed. \(error)")
            }
        }
        .sheet(isPresented: $showDonationDialog) {
            DonationDialog()
        }
    }

    private func toggleRecording() {
        Logger.log("Toggling recording... ", log: Logger.audio)
        if audio.isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        if isProcessing {
            Logger.log("Already processing, skipping", log: Logger.audio)
            return
        }
        Logger.log("Starting recording", log: Logger.audio)
        resetState()
        do {
            try audio.start()
            isProcessing = true

            Logger.log("Starting auto-stop timer", log: Logger.audio)
            recordingTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(RecordingAutoStopIntervalSeconds), repeats: false) { _ in
                Logger.log("Auto-stop timer fired", log: Logger.audio)
                DispatchQueue.main.async {
                    if audio.isRecording {
                        Logger.log("Auto-stopping recording after \(RecordingAutoStopIntervalSeconds) seconds", log: Logger.audio)
                        audio.stop()
                    }
                }
            }
        } catch {
            Logger.log("Start recording failed: \(error)", log: Logger.audio, type: .error)
        }
    }

    private func stopRecording() {
        Logger.log("Stopping recording", log: Logger.audio)
        recordingTimer?.invalidate()
        recordingTimer = nil
        audio.stop()
    }

    private func transcribeAudio(url: URL, source: TranscriptionSource, filename: String? = nil) {
        if isTranscribing {
            Logger.log("Already transcribing", log: Logger.audio)
            resetState(error: "Already transcribing. Please wait for the current transcription to finish.")
            return
        }
        isTranscribing = true

        Task {
            do {
                let voiceToTextModel = VoiceToTextFactory.createVoiceToText()
                let text = try await voiceToTextModel.process(filepath: url.path)

                audio.reset()
                if GenericHelper.logSensitiveData() {
                    Logger.log("Transcribed text: \(text)", log: Logger.audio)
                }

                let prompt = settings.currentPrompt
                if GenericHelper.logSensitiveData() {
                    Logger.log("Prompt: \(prompt)", log: Logger.audio)
                }
                var enhancedText = ""
                if !prompt.isEmpty {
                    let llm = LLMFactory.createLLM()
                    let isReady = try await llm.isReady()
                    if !isReady {
                        Logger.log("LLM is not ready", log: Logger.audio)
                        resetState(error: "LLM is not ready. Please download it from Setup Guide.")
                        return
                    }
                    enhancedText = try await llm.process(prompt: prompt, text: text)
                    if GenericHelper.logSensitiveData() {
                        Logger.log("Enhanced text: \(enhancedText)", log: Logger.audio)
                    }
                } else {
                    if GenericHelper.logSensitiveData() {
                        Logger.log("Using original text: \(text)", log: Logger.audio)
                    }
                    enhancedText = text
                }

                DispatchQueue.main.async {
                    Task {
                        await self.processText(text: enhancedText, source: source, filename: filename)
                    }
                }
            } catch {
                audio.reset()
                DispatchQueue.main.async {
                    Logger.log("Processing error: \(error)", log: Logger.audio, type: .error)
                    self.isProcessing = false
                    resetState(error: "Processing failed. \(error.localizedDescription)")
                }
            }
        }
    }

    private func resetState(message: String? = nil, status: String? = nil, error: String? = nil) {
        resultText = message ?? ""
        statusMessage = status ?? ""
        errorMessage = error ?? ""
        isProcessing = false
        isTranscribing = false
        recordingTimer?.invalidate()
        recordingTimer = nil
        audio.reset()
    }

    private func processText(text: String, source: TranscriptionSource, filename: String? = nil) async {
        defer {
            self.isTranscribing = false
            self.isProcessing = false
        }

        GenericHelper.copyToClipboard(text: text)
        let pasted = GenericHelper.paste(text: text)
        
        if pasted && settings.autoEnter {
            _ = GenericHelper.sendEnter()
        }

        self.resultText = text
        self.statusMessage = "✓ Copied to clipboard \(pasted ? "✓ Auto pasted" : "")\(pasted && settings.autoEnter ? " ✓ Auto enter" : "")"
        self.errorMessage = ""
        
        // Save to history
        TranscriptionHistory.shared.add(text: text, source: source, filename: filename)

        // Increment recording count and check for donation dialog
        if text.count >= 20 {
            settings.recordingCount += 1
        }
        if settings.recordingCount >= 10 && !settings.donationDialogShown {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.showDonationDialog = true
            }
        }
    }
}
