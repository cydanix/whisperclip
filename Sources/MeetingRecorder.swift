import Foundation
import AVFoundation
import FluidAudio

/// Callback types for meeting transcription
typealias MeetingTranscriptCallback = (MeetingSegment) -> Void
typealias MeetingErrorCallback = (Error) -> Void

/// Manages audio recording and streaming transcription for meetings
/// Uses FluidAudio for real-time transcription with speaker diarization
@MainActor
class MeetingRecorder: NSObject, ObservableObject {
    static let shared = MeetingRecorder()
    
    // MARK: - Published Properties
    
    @Published private(set) var isRecording = false
    @Published private(set) var currentLevel: Float = -160
    @Published private(set) var recordingDuration: TimeInterval = 0
    @Published private(set) var segmentCount: Int = 0
    @Published private(set) var lastError: String?
    @Published private(set) var activeSpeakers: [String] = []
    
    // MARK: - Audio Components
    
    private var audioRecorder: AVAudioRecorder?
    private var asrManager: AsrManager?
    private var diarizerManager: DiarizerManager?
    private var audioConverter: AudioConverter?
    
    // MARK: - State
    
    private var outputURL: URL?
    private var startTime: Date?
    private var levelTimer: Timer?
    private var chunkTimer: Timer?
    private var transcriptCallback: MeetingTranscriptCallback?
    private var errorCallback: MeetingErrorCallback?
    
    // Accumulated audio samples for transcription
    private var accumulatedSamples: [Float] = []
    private var lastTranscriptionTime: TimeInterval = 0
    private var lastProcessedSampleCount: Int = 0
    private var processedSegmentTexts: Set<String> = []
    
    // MARK: - Configuration
    
    private let sampleRate: Int = 16000  // Required by FluidAudio
    private let chunkDurationSeconds: TimeInterval = 5.0  // Process every 5 seconds
    
    private let recordingSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: 16000,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false
    ]
    
    // MARK: - Initialization
    
    private override init() {
        super.init()
        audioConverter = AudioConverter()
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
        
        // Initialize speaker diarization
        do {
            let diarizerModels = try await DiarizerModels.downloadIfNeeded()
            diarizerManager = DiarizerManager()
            diarizerManager?.initialize(models: diarizerModels)
            Logger.log("Speaker diarization initialized", log: Logger.general)
        } catch {
            Logger.log("Failed to initialize diarization (continuing without): \(error)", log: Logger.general, type: .error)
            // Continue without diarization - it's optional
        }
        
        // Create recording directory
        let recordingDir = getRecordingDirectory()
        try GenericHelper.folderCreate(folder: recordingDir)
        GenericHelper.folderCleanOldFiles(folder: recordingDir, days: 1)
        
        // Create output file
        let fileName = "meeting-\(GenericHelper.getUnixTimestamp()).wav"
        outputURL = recordingDir.appendingPathComponent(fileName)
        
        guard let url = outputURL else {
            throw MeetingRecorderError.invalidURL
        }
        
        // Setup audio recorder with 16kHz mono for FluidAudio compatibility
        audioRecorder = try AVAudioRecorder(url: url, settings: recordingSettings)
        audioRecorder?.delegate = self
        audioRecorder?.isMeteringEnabled = true
        audioRecorder?.prepareToRecord()
        
        guard audioRecorder?.record() == true else {
            throw MeetingRecorderError.recordingFailed
        }
        
        // Initialize state
        startTime = Date()
        isRecording = true
        segmentCount = 0
        lastError = nil
        lastTranscriptionTime = 0
        lastProcessedSampleCount = 0
        accumulatedSamples = []
        processedSegmentTexts = []
        
        // Start level monitoring
        startLevelMonitoring()
        
        // Start periodic chunk processing
        startChunkProcessing()
        
        Logger.log("Meeting recording started: \(url.path)", log: Logger.general)
    }
    
    func stopRecording() async -> URL? {
        guard isRecording else { return nil }
        
        // Stop timers
        levelTimer?.invalidate()
        levelTimer = nil
        chunkTimer?.invalidate()
        chunkTimer = nil
        
        // Stop audio recorder
        audioRecorder?.stop()
        isRecording = false
        
        // Process any remaining audio
        await processCurrentChunk(isFinal: true)
        
        // Cleanup
        let finalURL = outputURL
        cleanup()
        
        Logger.log("Meeting recording stopped", log: Logger.general)
        return finalURL
    }
    
    func cancelRecording() {
        levelTimer?.invalidate()
        levelTimer = nil
        chunkTimer?.invalidate()
        chunkTimer = nil
        
        audioRecorder?.stop()
        isRecording = false
        
        // Delete the recording file
        if let url = outputURL {
            GenericHelper.deleteFile(file: url)
        }
        
        cleanup()
        Logger.log("Meeting recording cancelled", log: Logger.general)
    }
    
    private func cleanup() {
        outputURL = nil
        transcriptCallback = nil
        errorCallback = nil
        accumulatedSamples = []
        processedSegmentTexts = []
        asrManager = nil
        diarizerManager = nil
    }
    
    // MARK: - Audio Level Monitoring
    
    private func startLevelMonitoring() {
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateLevel()
            }
        }
    }
    
    private func updateLevel() {
        guard let recorder = audioRecorder, isRecording else {
            currentLevel = -160
            return
        }
        
        recorder.updateMeters()
        currentLevel = recorder.averagePower(forChannel: 0)
        
        if let start = startTime {
            recordingDuration = Date().timeIntervalSince(start)
        }
    }
    
    // MARK: - Chunk Processing
    
    private func startChunkProcessing() {
        chunkTimer = Timer.scheduledTimer(withTimeInterval: chunkDurationSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.processCurrentChunk(isFinal: false)
            }
        }
    }
    
    private func processCurrentChunk(isFinal: Bool) async {
        guard let url = outputURL, let asrManager = asrManager else { return }
        
        // Check if file exists and has content
        guard GenericHelper.fileExists(file: url) else { return }
        
        let chunkStartTime = lastTranscriptionTime
        let chunkEndTime = recordingDuration
        
        // Need at least 1 second of new audio
        guard chunkEndTime > chunkStartTime + 1.0 else { return }
        
        do {
            // Load audio samples for diarization
            var audioSamples: [Float]?
            if let converter = audioConverter {
                audioSamples = try? converter.resampleAudioFile(url)
            }
            
            // Perform speaker diarization if we have enough samples
            var detectedSpeaker: Speaker = .unknown
            
            if let diarizer = diarizerManager,
               let samples = audioSamples,
               samples.count >= sampleRate * 3 {  // Minimum 3 seconds for diarization
                
                do {
                    let diarizationResult = try diarizer.performCompleteDiarization(samples, sampleRate: sampleRate)
                    
                    // Update active speakers list
                    let speakerManager = diarizer.speakerManager
                    activeSpeakers = speakerManager.speakerIds.compactMap { id in
                        speakerManager.getSpeaker(for: id)?.name
                    }
                    
                    // Find the dominant speaker in recent segments
                    if let lastSegment = diarizationResult.segments.last {
                        detectedSpeaker = mapToSpeaker(speakerId: lastSegment.speakerId)
                    }
                } catch {
                    Logger.log("Diarization error: \(error)", log: Logger.general, type: .error)
                }
            }
            
            // Transcribe the audio
            let transcriptionResult = try await asrManager.transcribe(url)
            
            guard !transcriptionResult.text.isEmpty else { return }
            
            // Clean and deduplicate
            let normalizedText = transcriptionResult.text.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Extract only new text (simple deduplication)
            let newText = extractNewText(normalizedText)
            guard !newText.isEmpty else { return }
            
            // Use text-based heuristic if diarization didn't detect speaker
            if detectedSpeaker == .unknown {
                detectedSpeaker = detectSpeakerFromText(newText)
            }
            
            // Create meeting segment
            let segment = MeetingSegment(
                speaker: detectedSpeaker,
                text: newText,
                startTime: chunkStartTime,
                endTime: chunkEndTime,
                confidence: detectedSpeaker == .unknown ? 0.7 : 0.9
            )
            
            segmentCount += 1
            lastTranscriptionTime = chunkEndTime
            processedSegmentTexts.insert(newText)
            
            transcriptCallback?(segment)
            
        } catch {
            Logger.log("Chunk processing error: \(error)", log: Logger.general, type: .error)
            lastError = error.localizedDescription
            if !isFinal {
                errorCallback?(error)
            }
        }
    }
    
    /// Extract text that hasn't been seen before
    private func extractNewText(_ fullText: String) -> String {
        // If this exact text was already processed, skip
        if processedSegmentTexts.contains(fullText) {
            return ""
        }
        
        // Check if fullText contains any previously processed text as prefix
        for processed in processedSegmentTexts {
            if fullText.hasPrefix(processed) {
                // Return only the new part
                let newPart = String(fullText.dropFirst(processed.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !newPart.isEmpty && !processedSegmentTexts.contains(newPart) {
                    return newPart
                }
            }
        }
        
        return fullText
    }
    
    // MARK: - Speaker Detection
    
    /// Map FluidAudio speaker ID to our Speaker enum
    private func mapToSpeaker(speakerId: String) -> Speaker {
        // FluidAudio assigns IDs like "Speaker_1", "Speaker_2", etc.
        // We map the first detected speaker to "Me" and others to "Other"
        if speakerId == "Speaker_1" || speakerId.contains("_1") {
            return .me
        } else if speakerId.contains("Speaker") {
            return .other
        }
        return .unknown
    }
    
    /// Fallback heuristic speaker detection from text
    private func detectSpeakerFromText(_ text: String) -> Speaker {
        let lowercased = text.lowercased()
        
        // Keywords that might indicate "me" speaking
        let meKeywords = ["i ", "i'm", "i've", "i'll", "my ", "we ", "we're", "we'll", "let me", "i think", "i believe"]
        
        // Keywords that might indicate "others" speaking
        let otherKeywords = ["you ", "you're", "you'll", "your ", "they ", "he ", "she ", "can you", "could you", "would you"]
        
        var meScore = 0
        var otherScore = 0
        
        for keyword in meKeywords {
            if lowercased.contains(keyword) {
                meScore += 1
            }
        }
        
        for keyword in otherKeywords {
            if lowercased.contains(keyword) {
                otherScore += 1
            }
        }
        
        if meScore == otherScore {
            return segmentCount % 2 == 0 ? .me : .other
        }
        
        return meScore > otherScore ? .me : .other
    }
    
    // MARK: - Helpers
    
    private func getRecordingDirectory() -> URL {
        let appDir = GenericHelper.getAppSupportDirectory()
        return appDir.appendingPathComponent("meeting_recordings")
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
    
    var normalizedLevel: Float {
        let minDb: Float = -60
        let maxDb: Float = 0
        let clampedLevel = max(minDb, min(maxDb, currentLevel))
        return (clampedLevel - minDb) / (maxDb - minDb)
    }
}

// MARK: - AVAudioRecorderDelegate

extension MeetingRecorder: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            if !flag {
                lastError = "Recording finished unexpectedly"
                errorCallback?(MeetingRecorderError.recordingFailed)
            }
        }
    }
    
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            let errorMsg = error?.localizedDescription ?? "Unknown encoding error"
            lastError = errorMsg
            errorCallback?(MeetingRecorderError.encodingError(errorMsg))
        }
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
