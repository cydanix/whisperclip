import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct FileTranscriptionView: View {
    @State private var selectedFileURL: URL?
    @State private var resultText: String = ""
    @State private var isProcessing: Bool = false
    @State private var statusMessage: String = ""
    @State private var errorMessage: String = ""
    @State private var showShareSheet: Bool = false
    @State private var isDragging: Bool = false
    @StateObject private var settings = SettingsStore.shared
    
    private let supportedTypes: [UTType] = [
        .audio,
        .mp3,
        .wav,
        .aiff,
        UTType(filenameExtension: "m4a") ?? .audio,
        UTType(filenameExtension: "flac") ?? .audio,
        UTType(filenameExtension: "ogg") ?? .audio,
        .mpeg4Audio
    ]
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.1),
                    Color(red: 0.03, green: 0.06, blue: 0.12),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                Spacer()
                
                VStack(spacing: 24) {
                    // Drop zone
                    ZStack {
                        // Glow effect
                        RoundedRectangle(cornerRadius: 20)
                            .fill(
                                RadialGradient(
                                    colors: [Color.blue.opacity(isDragging ? 0.3 : 0.1), Color.clear],
                                    center: .center,
                                    startRadius: 50,
                                    endRadius: 150
                                )
                            )
                            .frame(width: 280, height: 200)
                            .blur(radius: 30)
                        
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(
                                isDragging ? Color.blue : Color.white.opacity(0.2),
                                style: StrokeStyle(lineWidth: 2, dash: [8])
                            )
                            .frame(width: 260, height: 180)
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(Color.white.opacity(isDragging ? 0.08 : 0.03))
                            )
                        
                        VStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(Color.blue.opacity(0.2))
                                    .frame(width: 70, height: 70)
                                
                                Image(systemName: selectedFileURL != nil ? "doc.fill" : "arrow.down.doc.fill")
                                    .font(.system(size: 30))
                                    .foregroundColor(.blue)
                            }
                            
                            if let url = selectedFileURL {
                                VStack(spacing: 4) {
                                    Text(url.lastPathComponent)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                    
                                    Button {
                                        selectedFileURL = nil
                                        resultText = ""
                                        statusMessage = ""
                                        errorMessage = ""
                                    } label: {
                                        Text("Remove")
                                            .font(.caption)
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                            } else {
                                VStack(spacing: 4) {
                                    Text("Drop audio file here")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.white)
                                    
                                    Text("or click to browse")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                    }
                    .onTapGesture {
                        if !isProcessing {
                            selectFile()
                        }
                    }
                    .onDrop(of: [.audio, .fileURL], isTargeted: $isDragging) { providers in
                        handleDrop(providers: providers)
                    }
                    
                    // Supported formats
                    HStack(spacing: 8) {
                        ForEach(["MP3", "WAV", "M4A", "FLAC"], id: \.self) { format in
                            Text(format)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.gray)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.05))
                                .cornerRadius(4)
                        }
                    }
                    
                    // Transcribe button
                    if selectedFileURL != nil {
                        Button {
                            transcribeFile()
                        } label: {
                            HStack(spacing: 12) {
                                if isProcessing {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                        .scaleEffect(0.8)
                                        .tint(.white)
                                } else {
                                    Image(systemName: "waveform")
                                        .font(.system(size: 16))
                                }
                                Text(isProcessing ? "Transcribing..." : "Transcribe")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 16)
                            .background(
                                Capsule()
                                    .fill(LinearGradient(
                                        colors: [.blue, .blue.opacity(0.8)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ))
                            )
                            .shadow(color: .blue.opacity(0.4), radius: 10, y: 5)
                        }
                        .buttonStyle(.plain)
                        .disabled(isProcessing)
                    }
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
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        
        if provider.hasItemConformingToTypeIdentifier("public.file-url") {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, error in
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    DispatchQueue.main.async {
                        selectedFileURL = url
                        resultText = ""
                        statusMessage = ""
                        errorMessage = ""
                    }
                }
            }
            return true
        }
        return false
    }
    
    private func selectFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = supportedTypes
        
        if panel.runModal() == .OK {
            selectedFileURL = panel.url
            resultText = ""
            statusMessage = ""
            errorMessage = ""
        }
    }
    
    private func transcribeFile() {
        guard let url = selectedFileURL else { return }
        
        isProcessing = true
        errorMessage = ""
        resultText = ""
        statusMessage = ""
        
        Task {
            do {
                let voiceToTextModel = VoiceToTextFactory.createVoiceToText()
                let text = try await voiceToTextModel.process(filepath: url.path)
                
                if GenericHelper.logSensitiveData() {
                    Logger.log("Transcribed text from file: \(text)", log: Logger.audio)
                }
                
                let prompt = settings.currentPrompt
                var enhancedText = ""
                if !prompt.isEmpty {
                    let llm = LLMFactory.createLLM()
                    let isReady = try await llm.isReady()
                    if !isReady {
                        await MainActor.run {
                            errorMessage = "LLM is not ready. Please download it from Setup Guide."
                            isProcessing = false
                        }
                        return
                    }
                    enhancedText = try await llm.process(prompt: prompt, text: text)
                } else {
                    enhancedText = text
                }
                
                await MainActor.run {
                    resultText = enhancedText
                    GenericHelper.copyToClipboard(text: enhancedText)
                    statusMessage = "✓ Copied to clipboard"
                    isProcessing = false
                    
                    // Save to history
                    TranscriptionHistory.shared.add(text: enhancedText, source: .file, filename: url.lastPathComponent)
                }
            } catch {
                await MainActor.run {
                    Logger.log("File transcription error: \(error)", log: Logger.audio, type: .error)
                    errorMessage = "Transcription failed: \(error.localizedDescription)"
                    isProcessing = false
                }
            }
        }
    }
}
