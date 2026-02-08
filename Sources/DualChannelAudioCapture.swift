import Foundation
import AVFoundation
import ScreenCaptureKit

/// Audio source identifier for speaker detection
enum AudioSource {
    case microphone  // User's voice -> Speaker.me
    case system      // Other participants -> Speaker.other
    
    var speaker: Speaker {
        switch self {
        case .microphone: return .me
        case .system: return .other
        }
    }
}

/// Callback for audio chunks with source identification
typealias AudioChunkCallback = (AudioSource, [Float], TimeInterval) -> Void

/// Captures audio from both microphone and system audio separately
/// Uses AVAudioEngine for microphone and ScreenCaptureKit for system audio
@MainActor
class DualChannelAudioCapture: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    
    @Published private(set) var isCapturing = false
    @Published private(set) var micLevel: Float = -160
    @Published private(set) var systemLevel: Float = -160
    @Published private(set) var hasScreenCapturePermission = false
    @Published private(set) var lastError: String?
    
    // MARK: - Audio Engine (Microphone)
    
    private var audioEngine: AVAudioEngine?
    
    // MARK: - Screen Capture (System Audio)
    
    private var scStream: SCStream?
    
    // MARK: - Thread-safe buffers (using actor for synchronization)
    
    private let audioBuffers = AudioBufferActor()
    
    // MARK: - Configuration
    
    let sampleRate: Int = 16000
    private let chunkDuration: TimeInterval = 5.0  // Process every 5 seconds
    
    // MARK: - State
    
    /// Set once before capture starts, read from nonisolated audio callbacks
    nonisolated(unsafe) private var startTime: Date?
    private var chunkTimer: Timer?
    private var levelTimer: Timer?
    private var audioCallback: AudioChunkCallback?
    
    // MARK: - Initialization
    
    override init() {
        super.init()
    }
    
    // MARK: - Permission Check
    
    /// Check if screen capture permission is available (required for system audio)
    func checkPermissions() async -> Bool {
        do {
            // This will prompt for permission if not already granted
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            hasScreenCapturePermission = !content.displays.isEmpty
            return hasScreenCapturePermission
        } catch {
            Logger.log("Screen capture permission check failed: \(error)", log: Logger.general, type: .error)
            hasScreenCapturePermission = false
            return false
        }
    }
    
    // MARK: - Capture Control
    
    /// Start capturing from both microphone and system audio
    func startCapture(onAudioChunk: @escaping AudioChunkCallback) async throws {
        guard !isCapturing else {
            throw DualChannelError.alreadyCapturing
        }
        
        audioCallback = onAudioChunk
        startTime = Date()
        
        // Start microphone capture
        try startMicrophoneCapture()
        
        // Start system audio capture (if permission granted)
        if await checkPermissions() {
            try await startSystemAudioCapture()
        } else {
            Logger.log("System audio capture not available - only microphone will be used", log: Logger.general)
            lastError = "System audio permission not granted. Only your voice will be captured."
        }
        
        // Start chunk processing timer
        startChunkProcessing()
        
        // Start level monitoring
        startLevelMonitoring()
        
        isCapturing = true
        Logger.log("Dual channel audio capture started", log: Logger.general)
    }
    
    /// Stop all audio capture
    func stopCapture() async {
        guard isCapturing else { return }
        
        // Stop timers
        chunkTimer?.invalidate()
        chunkTimer = nil
        levelTimer?.invalidate()
        levelTimer = nil
        
        // Process any remaining audio
        processChunks(isFinal: true)
        
        // Stop microphone
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        
        // Stop system audio
        if let stream = scStream {
            try? await stream.stopCapture()
            scStream = nil
        }
        
        // Clear buffers
        await audioBuffers.clearAll()
        
        isCapturing = false
        audioCallback = nil
        
        Logger.log("Dual channel audio capture stopped", log: Logger.general)
    }
    
    // MARK: - Microphone Capture
    
    private func startMicrophoneCapture() throws {
        audioEngine = AVAudioEngine()
        
        guard let engine = audioEngine else {
            throw DualChannelError.microphoneSetupFailed
        }
        
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        // Create converter to 16kHz mono
        let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(sampleRate),
            channels: 1,
            interleaved: false
        )!
        
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw DualChannelError.microphoneSetupFailed
        }
        
        // Install tap on microphone input
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.processMicrophoneBuffer(buffer, converter: converter, outputFormat: outputFormat)
        }
        
        engine.prepare()
        try engine.start()
        
        Logger.log("Microphone capture started", log: Logger.general)
    }
    
    private func processMicrophoneBuffer(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter, outputFormat: AVAudioFormat) {
        // Convert to 16kHz mono
        let frameCount = AVAudioFrameCount(Double(buffer.frameLength) * Double(sampleRate) / buffer.format.sampleRate)
        
        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCount) else {
            return
        }
        
        var error: NSError?
        converter.convert(to: convertedBuffer, error: &error) { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        guard error == nil,
              let channelData = convertedBuffer.floatChannelData,
              convertedBuffer.frameLength > 0 else {
            return
        }
        
        // Copy samples to buffer
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: Int(convertedBuffer.frameLength)))
        
        // Update level from recent samples
        if samples.count > 0 {
            let rms = sqrt(samples.map { $0 * $0 }.reduce(0, +) / Float(samples.count))
            let db = 20 * log10(max(rms, 0.0001))
            Task { @MainActor in
                self.micLevel = db
            }
        }
        
        // Add to buffer using actor with elapsed time
        let elapsed = self.startTime.map { Date().timeIntervalSince($0) } ?? 0
        Task {
            await self.audioBuffers.appendMicSamples(samples, atTime: elapsed)
        }
    }
    
    // MARK: - System Audio Capture
    
    private func startSystemAudioCapture() async throws {
        // Get shareable content
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        
        guard let display = content.displays.first else {
            throw DualChannelError.noDisplayFound
        }
        
        // Configure to capture only audio (no video)
        let filter = SCContentFilter(display: display, excludingWindows: [])
        
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true  // Don't capture our own app's audio
        config.sampleRate = sampleRate
        config.channelCount = 1
        
        // Minimize video capture (we only want audio)
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)  // 1 FPS minimum
        
        // Create and start stream
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: DispatchQueue(label: "com.whisperclip.systemAudio"))
        
        try await stream.startCapture()
        scStream = stream
        
        Logger.log("System audio capture started", log: Logger.general)
    }
    
    // MARK: - Chunk Processing
    
    private func startChunkProcessing() {
        chunkTimer = Timer.scheduledTimer(withTimeInterval: chunkDuration, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.processChunks(isFinal: false)
            }
        }
    }
    
    private func processChunks(isFinal: Bool) {
        guard let callback = audioCallback else { return }
        
        // Process buffers asynchronously, using per-source timestamps
        Task {
            // Get microphone samples with their actual start time
            let micResult = await audioBuffers.getMicSamples()
            if micResult.samples.count >= sampleRate * 2 {  // At least 2 seconds
                Logger.log("Processing microphone chunk: \(micResult.samples.count) samples at \(String(format: "%.1f", micResult.startTime))s", log: Logger.general)
                callback(.microphone, micResult.samples, micResult.startTime)
            }
            
            // Get system audio samples with their actual start time
            let systemResult = await audioBuffers.getSystemSamples()
            if systemResult.samples.count >= sampleRate * 2 {  // At least 2 seconds
                Logger.log("Processing system audio chunk: \(systemResult.samples.count) samples at \(String(format: "%.1f", systemResult.startTime))s", log: Logger.general)
                callback(.system, systemResult.samples, systemResult.startTime)
            }
        }
    }
    
    // MARK: - Level Monitoring
    
    private func startLevelMonitoring() {
        // Levels are updated in the buffer processing callbacks
        // Timer not needed since we update on each buffer callback
        levelTimer = nil
    }
    
    // MARK: - Utility
    
    var elapsedTime: TimeInterval {
        startTime.map { Date().timeIntervalSince($0) } ?? 0
    }
    
    var formattedElapsedTime: String {
        let totalSeconds = Int(elapsedTime)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}

// MARK: - SCStreamDelegate

extension DualChannelAudioCapture: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            Logger.log("System audio stream stopped with error: \(error)", log: Logger.general, type: .error)
            self.lastError = error.localizedDescription
        }
    }
}

// MARK: - SCStreamOutput

extension DualChannelAudioCapture: SCStreamOutput {
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        
        // Extract audio samples from CMSampleBuffer
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        
        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        
        let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
        
        guard status == kCMBlockBufferNoErr, let data = dataPointer, length > 0 else { return }
        
        // Convert to Float samples (assuming 32-bit float format from ScreenCaptureKit)
        let floatCount = length / MemoryLayout<Float>.size
        let floatPointer = UnsafeRawPointer(data).bindMemory(to: Float.self, capacity: floatCount)
        let samples = Array(UnsafeBufferPointer(start: floatPointer, count: floatCount))
        
        // Calculate level
        if samples.count > 0 {
            let rms = sqrt(samples.map { $0 * $0 }.reduce(0, +) / Float(samples.count))
            let db = 20 * log10(max(rms, 0.0001))
            Task { @MainActor in
                self.systemLevel = db
            }
        }
        
        // Add to buffer using actor with elapsed time
        let elapsed = self.startTime.map { Date().timeIntervalSince($0) } ?? 0
        Task {
            await self.audioBuffers.appendSystemSamples(samples, atTime: elapsed)
        }
    }
}

// MARK: - Errors

// MARK: - Thread-safe Audio Buffer Actor

private actor AudioBufferActor {
    var micBuffer: [Float] = []
    var systemBuffer: [Float] = []
    var micBufferStartTime: TimeInterval?
    var systemBufferStartTime: TimeInterval?
    
    func appendMicSamples(_ samples: [Float], atTime time: TimeInterval) {
        if micBuffer.isEmpty {
            micBufferStartTime = time
        }
        micBuffer.append(contentsOf: samples)
    }
    
    func appendSystemSamples(_ samples: [Float], atTime time: TimeInterval) {
        if systemBuffer.isEmpty {
            systemBufferStartTime = time
        }
        systemBuffer.append(contentsOf: samples)
    }
    
    func getMicSamples() -> (samples: [Float], startTime: TimeInterval) {
        let samples = micBuffer
        let startTime = micBufferStartTime ?? 0
        micBuffer = []
        micBufferStartTime = nil
        return (samples, startTime)
    }
    
    func getSystemSamples() -> (samples: [Float], startTime: TimeInterval) {
        let samples = systemBuffer
        let startTime = systemBufferStartTime ?? 0
        systemBuffer = []
        systemBufferStartTime = nil
        return (samples, startTime)
    }
    
    func clearAll() {
        micBuffer = []
        systemBuffer = []
        micBufferStartTime = nil
        systemBufferStartTime = nil
    }
}

enum DualChannelError: LocalizedError {
    case alreadyCapturing
    case microphoneSetupFailed
    case systemAudioSetupFailed
    case noDisplayFound
    case permissionDenied
    
    var errorDescription: String? {
        switch self {
        case .alreadyCapturing:
            return "Audio capture is already in progress"
        case .microphoneSetupFailed:
            return "Failed to setup microphone capture"
        case .systemAudioSetupFailed:
            return "Failed to setup system audio capture"
        case .noDisplayFound:
            return "No display found for screen capture"
        case .permissionDenied:
            return "Screen recording permission denied. Grant permission in System Settings > Privacy & Security > Screen Recording"
        }
    }
}
