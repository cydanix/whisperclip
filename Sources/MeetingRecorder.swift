import Foundation
import AVFoundation
import FluidAudio

/// Callback types for meeting transcription
typealias MeetingTranscriptCallback = (MeetingSegment) -> Void
typealias MeetingErrorCallback = (Error) -> Void

/// Manages audio recording and streaming transcription for meetings
@MainActor
class MeetingRecorder: NSObject, ObservableObject {
    static let shared = MeetingRecorder()
    
    @Published private(set) var isRecording = false
    @Published private(set) var currentLevel: Float = -160
    @Published private(set) var recordingDuration: TimeInterval = 0
    @Published private(set) var segmentCount: Int = 0
    @Published private(set) var lastError: String?
    
    private var audioRecorder: AVAudioRecorder?
    private var asrManager: AsrManager?
    private var outputURL: URL?
    private var startTime: Date?
    private var levelTimer: Timer?
    private var segmentTimer: Timer?
    private var transcriptCallback: MeetingTranscriptCallback?
    private var errorCallback: MeetingErrorCallback?
    
    // Transcription buffer
    private var pendingAudioChunks: [URL] = []
    private var lastProcessedTime: TimeInterval = 0
    private var isProcessingChunk = false
    
    // Settings
    private let chunkDuration: TimeInterval = 10.0  // Process in 10-second chunks
    private let recordingSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 44_100,
        AVNumberOfChannelsKey: 1,  // Mono for better speech recognition
        AVEncoderBitRateKey: 128_000
    ]
    
    private override init() {
        super.init()
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
        
        // Create recording directory
        let recordingDir = getRecordingDirectory()
        try GenericHelper.folderCreate(folder: recordingDir)
        
        // Clean old recordings
        GenericHelper.folderCleanOldFiles(folder: recordingDir, days: 1)
        
        // Create output file
        let fileName = "meeting-\(GenericHelper.getUnixTimestamp()).m4a"
        outputURL = recordingDir.appendingPathComponent(fileName)
        
        guard let url = outputURL else {
            throw MeetingRecorderError.invalidURL
        }
        
        // Create and configure recorder
        audioRecorder = try AVAudioRecorder(url: url, settings: recordingSettings)
        audioRecorder?.delegate = self
        audioRecorder?.isMeteringEnabled = true
        audioRecorder?.prepareToRecord()
        
        // Start recording
        guard audioRecorder?.record() == true else {
            throw MeetingRecorderError.recordingFailed
        }
        
        // Initialize state
        startTime = Date()
        isRecording = true
        segmentCount = 0
        lastError = nil
        lastProcessedTime = 0
        
        // Start level monitoring
        startLevelMonitoring()
        
        // Start periodic transcription
        startPeriodicTranscription()
        
        Logger.log("Meeting recording started: \(url.path)", log: Logger.general)
    }
    
    func stopRecording() async -> URL? {
        guard isRecording else { return nil }
        
        // Stop timers
        levelTimer?.invalidate()
        levelTimer = nil
        segmentTimer?.invalidate()
        segmentTimer = nil
        
        // Stop recording
        audioRecorder?.stop()
        isRecording = false
        
        // Process any remaining audio
        if let url = outputURL {
            await processRemainingAudio()
        }
        
        let finalURL = outputURL
        Logger.log("Meeting recording stopped", log: Logger.general)
        
        return finalURL
    }
    
    func cancelRecording() {
        levelTimer?.invalidate()
        levelTimer = nil
        segmentTimer?.invalidate()
        segmentTimer = nil
        
        audioRecorder?.stop()
        isRecording = false
        
        // Delete the recording file
        if let url = outputURL {
            GenericHelper.deleteFile(file: url)
        }
        
        outputURL = nil
        transcriptCallback = nil
        errorCallback = nil
        
        Logger.log("Meeting recording cancelled", log: Logger.general)
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
    
    // MARK: - Periodic Transcription
    
    private func startPeriodicTranscription() {
        segmentTimer = Timer.scheduledTimer(withTimeInterval: chunkDuration, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.processCurrentChunk()
            }
        }
    }
    
    private func processCurrentChunk() async {
        guard isRecording, !isProcessingChunk, let manager = asrManager else { return }
        
        isProcessingChunk = true
        defer { isProcessingChunk = false }
        
        // Get current recording duration
        let currentDuration = recordingDuration
        
        // If we have new audio to process
        if currentDuration > lastProcessedTime + 1.0 {
            do {
                // We'll transcribe the full file each time but only use new segments
                // This is a simplified approach - a production app would use streaming
                guard let url = outputURL, GenericHelper.fileExists(file: url) else { return }
                
                let result = try await manager.transcribe(url)
                
                // Create segment from transcription
                if !result.text.isEmpty {
                    // Simple speaker detection: assume alternating speakers
                    // In production, use proper diarization from FluidAudio if available
                    let speaker = detectSpeaker(for: result.text)
                    
                    let segment = MeetingSegment(
                        speaker: speaker,
                        text: result.text,
                        startTime: lastProcessedTime,
                        endTime: currentDuration,
                        confidence: 0.9
                    )
                    
                    segmentCount += 1
                    transcriptCallback?(segment)
                }
                
                lastProcessedTime = currentDuration
                
            } catch {
                Logger.log("Chunk transcription error: \(error)", log: Logger.general, type: .error)
                lastError = error.localizedDescription
                errorCallback?(error)
            }
        }
    }
    
    private func processRemainingAudio() async {
        guard let manager = asrManager, let url = outputURL else { return }
        
        do {
            let result = try await manager.transcribe(url)
            
            if !result.text.isEmpty && recordingDuration > lastProcessedTime {
                let speaker = detectSpeaker(for: result.text)
                
                let segment = MeetingSegment(
                    speaker: speaker,
                    text: result.text,
                    startTime: lastProcessedTime,
                    endTime: recordingDuration,
                    confidence: 0.9
                )
                
                segmentCount += 1
                transcriptCallback?(segment)
            }
        } catch {
            Logger.log("Final transcription error: \(error)", log: Logger.general, type: .error)
        }
    }
    
    // MARK: - Speaker Detection
    
    /// Simple heuristic for speaker detection
    /// In production, this would use FluidAudio's diarization capabilities
    private func detectSpeaker(for text: String) -> Speaker {
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
        
        // Alternate based on segment count if no clear winner
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
        // Convert from dB (-160 to 0) to linear (0 to 1)
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
        }
    }
}
