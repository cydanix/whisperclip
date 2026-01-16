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
    
    private var audioEngine: AVAudioEngine?
    private var audioRecorder: AVAudioRecorder?
    private var asrManager: AsrManager?
    private var diarizerManager: DiarizerManager?
    private var audioStream: AudioStream?
    private var audioConverter: AudioConverter?
    
    // MARK: - State
    
    private var outputURL: URL?
    private var startTime: Date?
    private var levelTimer: Timer?
    private var transcriptCallback: MeetingTranscriptCallback?
    private var errorCallback: MeetingErrorCallback?
    
    // Accumulated audio samples for transcription
    private var accumulatedSamples: [Float] = []
    private var lastTranscriptionTime: TimeInterval = 0
    private var processedSegmentTexts: Set<String> = []
    
    // MARK: - Configuration
    
    private let sampleRate: Double = 16000  // Required by FluidAudio
    private let chunkDuration: TimeInterval = 5.0  // Process every 5 seconds
    private let chunkSkip: TimeInterval = 3.0  // Skip between chunks
    
    private let recordingSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 44_100,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 128_000
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
        
        // Create output file for backup recording
        let fileName = "meeting-\(GenericHelper.getUnixTimestamp()).m4a"
        outputURL = recordingDir.appendingPathComponent(fileName)
        
        guard let url = outputURL else {
            throw MeetingRecorderError.invalidURL
        }
        
        // Setup backup audio recorder (for file transcription if streaming fails)
        audioRecorder = try AVAudioRecorder(url: url, settings: recordingSettings)
        audioRecorder?.delegate = self
        audioRecorder?.isMeteringEnabled = true
        audioRecorder?.prepareToRecord()
        
        guard audioRecorder?.record() == true else {
            throw MeetingRecorderError.recordingFailed
        }
        
        // Setup streaming audio capture
        try setupAudioStream()
        
        // Initialize state
        startTime = Date()
        isRecording = true
        segmentCount = 0
        lastError = nil
        lastTranscriptionTime = 0
        accumulatedSamples = []
        processedSegmentTexts = []
        
        // Start level monitoring
        startLevelMonitoring()
        
        Logger.log("Meeting recording started with streaming: \(url.path)", log: Logger.general)
    }
    
    private func setupAudioStream() throws {
        // Initialize audio stream for chunked processing
        audioStream = AudioStream(
            chunkDuration: chunkDuration,
            chunkSkip: chunkSkip,
            streamStartTime: 0.0,
            chunkingStrategy: .useFixedSkip
        )
        
        // Bind chunk handler
        audioStream?.bind { [weak self] chunk, chunkInfo in
            Task { @MainActor in
                await self?.processAudioChunk(chunk, startTime: chunkInfo.startTime)
            }
        }
        
        // Setup audio engine for capture
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            throw MeetingRecorderError.recordingFailed
        }
        
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        // Install tap to capture audio
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            
            // Convert to 16kHz mono for FluidAudio
            if let convertedSamples = self.convertBufferTo16kMono(buffer, from: inputFormat) {
                Task { @MainActor in
                    self.accumulatedSamples.append(contentsOf: convertedSamples)
                    try? self.audioStream?.write(convertedSamples)
                }
            }
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        
        Logger.log("Audio stream setup complete", log: Logger.general)
    }
    
    private func convertBufferTo16kMono(_ buffer: AVAudioPCMBuffer, from format: AVAudioFormat) -> [Float]? {
        guard let channelData = buffer.floatChannelData else { return nil }
        
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(format.channelCount)
        let inputSampleRate = format.sampleRate
        
        // Mix down to mono
        var monoSamples = [Float](repeating: 0, count: frameCount)
        for frame in 0..<frameCount {
            var sum: Float = 0
            for channel in 0..<channelCount {
                sum += channelData[channel][frame]
            }
            monoSamples[frame] = sum / Float(channelCount)
        }
        
        // Resample to 16kHz if needed
        if inputSampleRate != sampleRate {
            let ratio = sampleRate / inputSampleRate
            let outputCount = Int(Double(frameCount) * ratio)
            var resampled = [Float](repeating: 0, count: outputCount)
            
            for i in 0..<outputCount {
                let srcIndex = Double(i) / ratio
                let index = Int(srcIndex)
                let fraction = Float(srcIndex - Double(index))
                
                if index + 1 < frameCount {
                    resampled[i] = monoSamples[index] * (1 - fraction) + monoSamples[index + 1] * fraction
                } else if index < frameCount {
                    resampled[i] = monoSamples[index]
                }
            }
            return resampled
        }
        
        return monoSamples
    }
    
    func stopRecording() async -> URL? {
        guard isRecording else { return nil }
        
        // Stop audio engine
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        
        // Stop level timer
        levelTimer?.invalidate()
        levelTimer = nil
        
        // Stop audio recorder
        audioRecorder?.stop()
        isRecording = false
        
        // Process any remaining audio
        await processRemainingAudio()
        
        // Cleanup
        let finalURL = outputURL
        cleanup()
        
        Logger.log("Meeting recording stopped", log: Logger.general)
        return finalURL
    }
    
    func cancelRecording() {
        levelTimer?.invalidate()
        levelTimer = nil
        
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        
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
        audioStream = nil
        accumulatedSamples = []
        processedSegmentTexts = []
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
    
    // MARK: - Audio Processing with Diarization
    
    private func processAudioChunk(_ samples: [Float], startTime: TimeInterval) async {
        guard isRecording, let asrManager = asrManager else { return }
        
        let chunkStartTime = startTime
        let chunkEndTime = startTime + chunkDuration
        
        do {
            // Perform speaker diarization on the chunk
            var speakerSegments: [(speaker: Speaker, startTime: TimeInterval, endTime: TimeInterval)] = []
            
            if let diarizer = diarizerManager, samples.count >= Int(sampleRate * 3) {
                // Minimum 3 seconds for diarization
                let diarizationResult = try diarizer.performCompleteDiarization(samples, sampleRate: Int(sampleRate))
                
                // Update active speakers
                if let speakerManager = diarizer.speakerManager {
                    activeSpeakers = speakerManager.speakerIds.compactMap { id in
                        speakerManager.getSpeaker(for: id)?.name
                    }
                }
                
                // Map diarization segments to our speaker model
                for segment in diarizationResult.segments {
                    let speaker = mapToSpeaker(speakerId: segment.speakerId)
                    speakerSegments.append((
                        speaker: speaker,
                        startTime: chunkStartTime + segment.startTimeSeconds,
                        endTime: chunkStartTime + segment.endTimeSeconds
                    ))
                }
            }
            
            // Transcribe the audio chunk
            // Save chunk to temporary file for ASR
            let tempURL = getRecordingDirectory().appendingPathComponent("temp_chunk.wav")
            try saveWavFile(samples: samples, to: tempURL, sampleRate: Int(sampleRate))
            
            let transcriptionResult = try await asrManager.transcribe(tempURL)
            
            // Clean up temp file
            GenericHelper.deleteFile(file: tempURL)
            
            guard !transcriptionResult.text.isEmpty else { return }
            
            // Skip if we've already processed this text (deduplication)
            let normalizedText = transcriptionResult.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if processedSegmentTexts.contains(normalizedText) {
                return
            }
            processedSegmentTexts.insert(normalizedText)
            
            // Create meeting segment(s) based on diarization
            if speakerSegments.isEmpty {
                // No diarization - create single segment with heuristic speaker detection
                let speaker = detectSpeakerFromText(normalizedText)
                let segment = MeetingSegment(
                    speaker: speaker,
                    text: normalizedText,
                    startTime: chunkStartTime,
                    endTime: chunkEndTime,
                    confidence: 0.9
                )
                segmentCount += 1
                transcriptCallback?(segment)
            } else {
                // Use diarization results - split text by speaker segments
                // For simplicity, assign the full text to the dominant speaker
                let dominantSpeaker = findDominantSpeaker(in: speakerSegments)
                let segment = MeetingSegment(
                    speaker: dominantSpeaker,
                    text: normalizedText,
                    startTime: chunkStartTime,
                    endTime: chunkEndTime,
                    confidence: 0.95
                )
                segmentCount += 1
                transcriptCallback?(segment)
            }
            
            lastTranscriptionTime = chunkEndTime
            
        } catch {
            Logger.log("Chunk processing error: \(error)", log: Logger.general, type: .error)
            lastError = error.localizedDescription
            errorCallback?(error)
        }
    }
    
    private func processRemainingAudio() async {
        guard let asrManager = asrManager,
              accumulatedSamples.count > Int(sampleRate * 2) else { return }
        
        // Process any audio after the last transcription
        let remainingStart = lastTranscriptionTime
        let remainingEnd = recordingDuration
        
        // Get samples from the last processed time
        let startSample = Int(lastTranscriptionTime * sampleRate)
        guard startSample < accumulatedSamples.count else { return }
        
        let remainingSamples = Array(accumulatedSamples[startSample...])
        guard remainingSamples.count > Int(sampleRate) else { return }
        
        do {
            // Save and transcribe remaining audio
            let tempURL = getRecordingDirectory().appendingPathComponent("temp_final.wav")
            try saveWavFile(samples: remainingSamples, to: tempURL, sampleRate: Int(sampleRate))
            
            let result = try await asrManager.transcribe(tempURL)
            GenericHelper.deleteFile(file: tempURL)
            
            guard !result.text.isEmpty else { return }
            
            let normalizedText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !processedSegmentTexts.contains(normalizedText) else { return }
            
            // Perform diarization on remaining audio
            var speaker = detectSpeakerFromText(normalizedText)
            
            if let diarizer = diarizerManager, remainingSamples.count >= Int(sampleRate * 3) {
                let diarizationResult = try diarizer.performCompleteDiarization(remainingSamples, sampleRate: Int(sampleRate))
                if let firstSegment = diarizationResult.segments.first {
                    speaker = mapToSpeaker(speakerId: firstSegment.speakerId)
                }
            }
            
            let segment = MeetingSegment(
                speaker: speaker,
                text: normalizedText,
                startTime: remainingStart,
                endTime: remainingEnd,
                confidence: 0.9
            )
            
            segmentCount += 1
            transcriptCallback?(segment)
            
        } catch {
            Logger.log("Final transcription error: \(error)", log: Logger.general, type: .error)
        }
    }
    
    // MARK: - Speaker Mapping
    
    /// Map FluidAudio speaker ID to our Speaker enum
    private func mapToSpeaker(speakerId: String) -> Speaker {
        // FluidAudio assigns IDs like "Speaker_1", "Speaker_2", etc.
        // We map the first detected speaker to "Me" and others to "Other"
        if speakerId == "Speaker_1" || speakerId.hasSuffix("_1") {
            return .me
        } else {
            return .other
        }
    }
    
    /// Find the speaker with the most speaking time in a set of segments
    private func findDominantSpeaker(in segments: [(speaker: Speaker, startTime: TimeInterval, endTime: TimeInterval)]) -> Speaker {
        var speakerDurations: [Speaker: TimeInterval] = [:]
        
        for segment in segments {
            let duration = segment.endTime - segment.startTime
            speakerDurations[segment.speaker, default: 0] += duration
        }
        
        return speakerDurations.max(by: { $0.value < $1.value })?.key ?? .unknown
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
    
    // MARK: - WAV File Helpers
    
    private func saveWavFile(samples: [Float], to url: URL, sampleRate: Int) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        
        let channelData = buffer.floatChannelData![0]
        for (index, sample) in samples.enumerated() {
            channelData[index] = sample
        }
        
        let audioFile = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true
        ])
        
        try audioFile.write(from: buffer)
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
