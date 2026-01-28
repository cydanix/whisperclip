import Foundation
import AVFoundation
import FluidAudio

/// Callback types for meeting transcription
typealias MeetingTranscriptCallback = (MeetingSegment) -> Void
typealias MeetingErrorCallback = (Error) -> Void

/// Manages audio recording and streaming transcription for meetings
/// Uses dual-channel capture: microphone (Me) and system audio (Other)
@MainActor
class MeetingRecorder: NSObject, ObservableObject {
    static let shared = MeetingRecorder()
    
    // MARK: - Published Properties
    
    @Published private(set) var isRecording = false
    @Published private(set) var micLevel: Float = -160
    @Published private(set) var systemLevel: Float = -160
    @Published private(set) var recordingDuration: TimeInterval = 0
    @Published private(set) var segmentCount: Int = 0
    @Published private(set) var lastError: String?
    @Published private(set) var activeSpeakers: [String] = ["Me", "Other"]
    @Published private(set) var hasSystemAudioPermission = false
    
    // MARK: - Audio Components
    
    private var dualCapture: DualChannelAudioCapture?
    private var asrManager: AsrManager?
    
    // MARK: - State
    
    private var startTime: Date?
    private var durationTimer: Timer?
    private var transcriptCallback: MeetingTranscriptCallback?
    private var errorCallback: MeetingErrorCallback?
    
    // Text deduplication per speaker
    private var processedMicTexts: Set<String> = []
    private var processedSystemTexts: Set<String> = []
    
    // Transcription queue to prevent concurrent CoreML predictions
    private let transcriptionQueue = TranscriptionQueue()
    
    // MARK: - Configuration
    
    private let sampleRate: Int = 16000  // Required by FluidAudio
    
    // MARK: - Initialization
    
    private override init() {
        super.init()
    }
    
    // MARK: - Permission Check
    
    /// Check if system audio capture permission is available
    func checkSystemAudioPermission() async -> Bool {
        let capture = DualChannelAudioCapture()
        hasSystemAudioPermission = await capture.checkPermissions()
        return hasSystemAudioPermission
    }
    
    // MARK: - Recording Control
    
    func startRecording(
        onTranscript: @escaping MeetingTranscriptCallback,
        onError: @escaping MeetingErrorCallback
    ) async throws {
        guard !isRecording else {
            throw MeetingRecorderError.alreadyRecording
        }
        
        // Store callbacks
        transcriptCallback = onTranscript
        errorCallback = onError
        
        // Initialize ASR manager
        do {
            asrManager = try await LocalParakeet.loadModel()
        } catch {
            Logger.log("Failed to load ASR model: \(error)", log: Logger.general, type: .error)
            throw MeetingRecorderError.modelLoadFailed(error.localizedDescription)
        }
        
        // Create dual channel capture
        dualCapture = DualChannelAudioCapture()
        
        guard let capture = dualCapture else {
            throw MeetingRecorderError.recordingFailed
        }
        
        // Start dual channel capture
        do {
            try await capture.startCapture { [weak self] source, samples, startTime in
                guard let self = self else { return }
                // Use transcription queue to serialize CoreML predictions
                Task {
                    await self.transcriptionQueue.enqueue(
                        source: source,
                        samples: samples,
                        startTime: startTime,
                        processor: { src, samp, time in
                            await self.processAudioChunk(source: src, samples: samp, startTime: time)
                        }
                    )
                }
            }
        } catch {
            Logger.log("Failed to start dual capture: \(error)", log: Logger.general, type: .error)
            throw MeetingRecorderError.recordingFailed
        }
        
        // Initialize state
        startTime = Date()
        isRecording = true
        segmentCount = 0
        lastError = nil
        processedMicTexts = []
        processedSystemTexts = []
        hasSystemAudioPermission = capture.hasScreenCapturePermission
        
        // Start duration timer
        startDurationTimer()
        
        // Update active speakers based on permissions
        if hasSystemAudioPermission {
            activeSpeakers = ["Me", "Other"]
        } else {
            activeSpeakers = ["Me"]
            lastError = "System audio not available. Only your voice will be captured."
        }
        
        Logger.log("Meeting recording started with dual-channel capture", log: Logger.general)
    }
    
    func stopRecording() async -> URL? {
        guard isRecording else { return nil }
        
        // Stop duration timer
        durationTimer?.invalidate()
        durationTimer = nil
        
        // Stop dual capture
        if let capture = dualCapture {
            await capture.stopCapture()
        }
        
        isRecording = false
        
        // Cleanup
        cleanup()
        
        Logger.log("Meeting recording stopped", log: Logger.general)
        return nil  // No file URL since we process in memory
    }
    
    func cancelRecording() {
        durationTimer?.invalidate()
        durationTimer = nil
        
        if let capture = dualCapture {
            Task {
                await capture.stopCapture()
            }
        }
        
        isRecording = false
        cleanup()
        Logger.log("Meeting recording cancelled", log: Logger.general)
    }
    
    private func cleanup() {
        transcriptCallback = nil
        errorCallback = nil
        processedMicTexts = []
        processedSystemTexts = []
        asrManager = nil
        dualCapture = nil
    }
    
    // MARK: - Duration Timer
    
    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateDuration()
            }
        }
    }
    
    private func updateDuration() {
        guard let start = startTime else { return }
        recordingDuration = Date().timeIntervalSince(start)
        
        // Update levels from dual capture
        if let capture = dualCapture {
            micLevel = capture.micLevel
            systemLevel = capture.systemLevel
        }
    }
    
    // MARK: - Audio Processing
    
    private func processAudioChunk(source: AudioSource, samples: [Float], startTime: TimeInterval) async {
        guard let asrManager = asrManager else {
            Logger.log("processAudioChunk: asrManager not available", log: Logger.general, type: .error)
            return
        }
        
        guard samples.count >= sampleRate * 2 else {
            Logger.log("processAudioChunk: not enough samples (\(samples.count))", log: Logger.general)
            return
        }
        
        let speaker = source.speaker
        let sourceName = source == .microphone ? "mic" : "system"
        
        Logger.log("processAudioChunk: processing \(sourceName) chunk with \(samples.count) samples", log: Logger.general)
        
        // Create temp WAV file for transcription
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("meeting_\(sourceName)_\(UUID().uuidString).wav")
        
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        do {
            // Write samples to WAV file
            try writeWAVFile(samples: samples, to: tempURL)
            
            // Transcribe
            let transcriptionResult = try await asrManager.transcribe(tempURL)
            
            guard !transcriptionResult.text.isEmpty else {
                Logger.log("processAudioChunk: empty transcription from \(sourceName)", log: Logger.general)
                return
            }
            
            // Clean and deduplicate based on source
            let normalizedText = transcriptionResult.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let newText = extractNewText(normalizedText, for: source)
            
            guard !newText.isEmpty else {
                Logger.log("processAudioChunk: no new text after deduplication from \(sourceName)", log: Logger.general)
                return
            }
            
            // Calculate end time
            let chunkDuration = Double(samples.count) / Double(sampleRate)
            let endTime = startTime + chunkDuration
            
            // Create segment with correct speaker
            let segment = MeetingSegment(
                speaker: speaker,
                text: newText,
                startTime: startTime,
                endTime: endTime,
                confidence: 0.95  // High confidence since we know the source
            )
            
            segmentCount += 1
            
            // Store for deduplication
            if source == .microphone {
                processedMicTexts.insert(newText)
            } else {
                processedSystemTexts.insert(newText)
            }
            
            Logger.log("processAudioChunk: created \(speaker.displayName) segment #\(segmentCount): '\(newText.prefix(50))'", log: Logger.general)
            
            transcriptCallback?(segment)
            
        } catch {
            Logger.log("processAudioChunk: error processing \(sourceName): \(error)", log: Logger.general, type: .error)
            lastError = error.localizedDescription
        }
    }
    
    /// Extract text that hasn't been seen before for this source
    private func extractNewText(_ fullText: String, for source: AudioSource) -> String {
        let processedTexts = source == .microphone ? processedMicTexts : processedSystemTexts
        
        // If this exact text was already processed, skip
        if processedTexts.contains(fullText) {
            return ""
        }
        
        // Check if fullText contains any previously processed text as prefix
        for processed in processedTexts {
            if fullText.hasPrefix(processed) {
                // Return only the new part
                let newPart = String(fullText.dropFirst(processed.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !newPart.isEmpty && !processedTexts.contains(newPart) {
                    return newPart
                }
            }
        }
        
        return fullText
    }
    
    // MARK: - Helpers
    
    /// Write float samples to a WAV file with proper header
    private func writeWAVFile(samples: [Float], to url: URL) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1)!
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
            throw MeetingRecorderError.transcriptionFailed("Failed to create output buffer")
        }
        
        // Copy samples to buffer
        guard let floatData = buffer.floatChannelData else {
            throw MeetingRecorderError.transcriptionFailed("Failed to get buffer channel data")
        }
        
        for (i, sample) in samples.enumerated() {
            floatData[0][i] = sample
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        
        // Write to file
        let outputFile = try AVAudioFile(forWriting: url, settings: format.settings)
        try outputFile.write(from: buffer)
    }
    
    var formattedDuration: String {
        let totalSeconds = Int(recordingDuration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    /// Combined normalized level (max of mic and system)
    var normalizedLevel: Float {
        let level = max(micLevel, systemLevel)
        let minDb: Float = -60
        let maxDb: Float = 0
        let clampedLevel = max(minDb, min(maxDb, level))
        return (clampedLevel - minDb) / (maxDb - minDb)
    }
    
    /// Backward compatibility
    var currentLevel: Float {
        max(micLevel, systemLevel)
    }
}

// MARK: - Transcription Queue

/// Serializes transcription requests to prevent concurrent CoreML predictions
/// which can cause crashes due to thread-safety issues
private actor TranscriptionQueue {
    private var isProcessing = false
    private var pendingRequests: [(AudioSource, [Float], TimeInterval, @MainActor (AudioSource, [Float], TimeInterval) async -> Void)] = []
    
    func enqueue(
        source: AudioSource,
        samples: [Float],
        startTime: TimeInterval,
        processor: @escaping @MainActor (AudioSource, [Float], TimeInterval) async -> Void
    ) async {
        if isProcessing {
            // Queue for later processing
            pendingRequests.append((source, samples, startTime, processor))
            return
        }
        
        isProcessing = true
        await processor(source, samples, startTime)
        isProcessing = false
        
        // Process next in queue if any
        await processNext()
    }
    
    private func processNext() async {
        guard !pendingRequests.isEmpty else { return }
        
        let (source, samples, startTime, processor) = pendingRequests.removeFirst()
        isProcessing = true
        await processor(source, samples, startTime)
        isProcessing = false
        
        // Continue processing queue
        await processNext()
    }
}

// MARK: - Errors

enum MeetingRecorderError: LocalizedError {
    case alreadyRecording
    case modelLoadFailed(String)
    case invalidURL
    case recordingFailed
    case encodingError(String)
    case transcriptionFailed(String)
    case diarizationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return "Recording is already in progress"
        case .modelLoadFailed(let message):
            return "Failed to load transcription model: \(message)"
        case .invalidURL:
            return "Invalid recording URL"
        case .recordingFailed:
            return "Failed to start recording"
        case .encodingError(let message):
            return "Audio encoding error: \(message)"
        case .transcriptionFailed(let message):
            return "Transcription failed: \(message)"
        case .diarizationFailed(let message):
            return "Speaker diarization failed: \(message)"
        }
    }
}
