import SwiftUI
import AVFoundation
import AppKit
import Combine

struct ContentView: View {
    @ObservedObject private var audio = AudioRecorder.shared
    @State private var resultText: String = ""
    @State private var isProcessing: Bool = false
    @State private var isTranscribing: Bool = false
    @State private var showShareSheet: Bool = false
    @State private var statusMessage: String = ""
    @State private var errorMessage: String = ""
    @State private var startedByHotkey = false
    @State private var overlayShown = false

    @StateObject private var hotkeyManager = HotkeyManager.shared
    @StateObject private var settings = SettingsStore.shared
    @State private var recordingTimer: Timer? = nil
    @State private var transcriptionUpdateTimer: Timer? = nil
    @State private var isFullScreen: Bool = false

    init() {
    }

    var body: some View {
        ZStack {
            (isFullScreen ? Color.black : Color.black)
                .ignoresSafeArea()
            VStack(spacing: 20) {
                WaveformView(audio: audio)
                    .padding(.bottom, audio.isRecording ? -10 : 0)

                // Show mic image only in idle mode
                if !audio.isRecording && !isProcessing {
                    Image(systemName: "mic")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 128, height: 128)
                        .padding(.bottom, 10)
                }

                Text(isProcessing ? (audio.isRecording ? "Recording…" : "Processing...") : "Idle")
                    .font(.title2)
                    .foregroundColor(isProcessing ? (audio.isRecording ? .red : .orange) : .white)

                Button {
                    toggleRecording()
                } label: {
                    Label(audio.isRecording ? "Stop" : "Record",
                          systemImage: audio.isRecording ? "stop.fill" : "circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isProcessing && !audio.isRecording)

                if !resultText.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Result")
                                .font(.headline)
                                .foregroundColor(.white)

                            if !statusMessage.isEmpty {
                                Text(statusMessage)
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }

                            Spacer()

                            Button {
                                showShareSheet = true
                            } label: {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.bordered)
                            .disabled(resultText.isEmpty || isProcessing)
                        }

                        ScrollViewReader { proxy in
                            ScrollView {
                                Text(resultText)
                                    .padding()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.white.opacity(0.08))
                                    .cornerRadius(8)
                                    .textSelection(.enabled)
                                    .foregroundColor(.white)
                                    .id("resultTextBottom")
                            }
                            .frame(height: 150)
                            .onChange(of: resultText) {
                                withAnimation {
                                    proxy.scrollTo("resultTextBottom", anchor: .bottom)
                                }
                            }
                        }
                    }
                    .padding(.top, 16)
                    .sheet(isPresented: $showShareSheet, onDismiss: {
                        showShareSheet = false
                    }) {
                        VStack {
                            HStack {
                                Spacer()
                                Button {
                                    showShareSheet = false
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.gray)
                                }
                                .buttonStyle(.plain)
                                .padding([.top, .trailing], 10)
                            }

                            if #available(macOS 13.0, *) {
                                ShareLink("Share", item: resultText)
                                    .padding()
                            } else {
                                Text("Sharing not available on this OS version")
                                    .padding()
                            }
                        }
                    }
                }

                if !errorMessage.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Error")
                            .font(.headline)
                            .foregroundColor(.red)

                        ScrollView {
                            Text(errorMessage)
                                .font(.body)
                                .foregroundColor(.red)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.white.opacity(0.08))
                                .cornerRadius(8)
                                .textSelection(.enabled)
                        }
                        .frame(height: 100)
                    }
                    .padding(.top, 16)
                }
            }
            .padding(40)
        }
        .overlay(WindowAccessor(isFullScreen: $isFullScreen).frame(width: 0, height: 0))
        .frame(minWidth: 400, minHeight: 500)
        .foregroundColor(.white)
        .onAppear {
            Logger.log("ContentView appeared", log: Logger.general)
            hotkeyManager.setAction(action: {
                Logger.log("Hotkey action triggered", log: Logger.hotkey)
                self.startedByHotkey = true
                self.toggleRecording()
                self.startedByHotkey = false
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

                transcribeAudio(url: fileUrl)
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
    }

    private func toggleRecording() {
        Logger.log("Toggling recording... ", log: Logger.audio)
        if audio.isRecording {
            Logger.log("Stopping recording", log: Logger.audio)
            recordingTimer?.invalidate()
            recordingTimer = nil
            stopTranscriptionUpdates()
            audio.stop()
        } else {
            if isProcessing {
                Logger.log("Already processing, skipping", log: Logger.audio)
                return
            }
            Logger.log("Starting recording", log: Logger.audio)
            resetState()
            do {
                try audio.start()
                isProcessing = true
                startTranscriptionUpdates()

                // Start auto-stop timer
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
    }



    private func transcribeAudio(url: URL) {
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
                        await self.processText(text: enhancedText)
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

    private func startTranscriptionUpdates() {
        // Update transcription text every 200ms during processing
        transcriptionUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            DispatchQueue.main.async {
            }
        }
    }

    private func stopTranscriptionUpdates() {
        transcriptionUpdateTimer?.invalidate()
        transcriptionUpdateTimer = nil
    }

    private func resetState(message: String? = nil, status: String? = nil, error: String? = nil) {
        resultText = message ?? ""
        statusMessage = status ?? ""
        errorMessage = error ?? ""
        isProcessing = false
        isTranscribing = false
        recordingTimer?.invalidate()
        recordingTimer = nil
        stopTranscriptionUpdates()
        audio.reset()
    }

    private func processText(text: String) async {
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
    }
}

// Helper to access NSWindow and observe full screen changes
private struct WindowAccessor: NSViewRepresentable {
    @Binding var isFullScreen: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                context.coordinator.observe(window: window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window {
            context.coordinator.observe(window: window)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isFullScreen: $isFullScreen)
    }

    class Coordinator: NSObject, NSWindowDelegate {
        var isFullScreen: Binding<Bool>
        private var observedWindow: NSWindow?

        init(isFullScreen: Binding<Bool>) {
            self.isFullScreen = isFullScreen
        }

        func observe(window: NSWindow) {
            if observedWindow !== window {
                observedWindow?.delegate = nil
                observedWindow = window
                window.delegate = self
                isFullScreen.wrappedValue = (window.styleMask.contains(.fullScreen))
            }
        }

        func windowDidEnterFullScreen(_ notification: Notification) {
            isFullScreen.wrappedValue = true
        }
        func windowDidExitFullScreen(_ notification: Notification) {
            isFullScreen.wrappedValue = false
        }
    }
}
