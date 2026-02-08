import Foundation
import Combine

/// Orchestrates the complete meeting lifecycle
@MainActor
class MeetingSession: ObservableObject {
    static let shared = MeetingSession()
    
    // MARK: - Published Properties
    
    @Published private(set) var isActive: Bool = false
    @Published private(set) var currentMeetingId: UUID?
    @Published private(set) var status: SessionStatus = .idle
    @Published private(set) var liveTranscript: [MeetingSegment] = []
    @Published private(set) var errorMessage: String?
    @Published var autoDetectEnabled: Bool = SettingsStore.shared.meetingAutoDetect {
        didSet {
            SettingsStore.shared.meetingAutoDetect = autoDetectEnabled
            if autoDetectEnabled {
                detector.startDetection()
            } else {
                detector.stopDetection()
            }
        }
    }
    
    // MARK: - Dependencies
    
    private let storage = MeetingStorage.shared
    private let recorder = MeetingRecorder.shared
    private let detector = MeetingDetector.shared
    private let ai = MeetingAI.shared
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    private var autoSaveTimer: Timer?
    
    // MARK: - Status
    
    enum SessionStatus: String {
        case idle = "Ready"
        case starting = "Starting..."
        case recording = "Recording"
        case stopping = "Stopping..."
        case processing = "Processing..."
        case completed = "Completed"
        case failed = "Failed"
        
        var isActive: Bool {
            switch self {
            case .starting, .recording, .stopping, .processing:
                return true
            default:
                return false
            }
        }
    }
    
    // MARK: - Initialization
    
    private init() {
        setupObservers()
        // Resume detection if user previously enabled it
        if autoDetectEnabled {
            detector.startDetection()
        }
    }
    
    private func setupObservers() {
        // Listen for meeting app detection
        NotificationCenter.default.publisher(for: .meetingAppDetected)
            .sink { [weak self] notification in
                Task { @MainActor in
                    if let source = notification.object as? MeetingSource {
                        self?.handleMeetingAppDetected(source: source)
                    }
                }
            }
            .store(in: &cancellables)
        
        // Listen for meeting app closed
        NotificationCenter.default.publisher(for: .meetingAppClosed)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.handleMeetingAppClosed()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Meeting Control
    
    /// Start a new meeting session
    func startMeeting(title: String? = nil, source: MeetingSource = .manual) async {
        guard !isActive else {
            Logger.log("Meeting already active, ignoring start request", log: Logger.general)
            return
        }
        
        status = .starting
        errorMessage = nil
        liveTranscript = []
        
        do {
            // Create meeting in storage
            let meetingTitle = title ?? generateMeetingTitle(source: source)
            let meeting = storage.create(title: meetingTitle, source: source)
            currentMeetingId = meeting.id
            
            // Start recording with transcription callback
            // Capture meetingId to ensure segments are saved even during shutdown
            let capturedMeetingId = meeting.id
            try await recorder.startRecording(
                onTranscript: { [weak self] segment in
                    Task { @MainActor in
                        self?.handleNewSegment(segment, forMeetingId: capturedMeetingId)
                    }
                },
                onError: { [weak self] error in
                    Task { @MainActor in
                        self?.handleRecordingError(error)
                    }
                }
            )
            
            isActive = true
            status = .recording
            
            // Start auto-save timer
            startAutoSave()
            
            Logger.log("Meeting session started: \(meeting.id)", log: Logger.general)
            
        } catch {
            Logger.log("Failed to start meeting: \(error)", log: Logger.general, type: .error)
            status = .failed
            errorMessage = error.localizedDescription
            isActive = false
            currentMeetingId = nil
        }
    }
    
    /// Stop the current meeting and generate summary
    func stopMeeting() async {
        guard isActive, let meetingId = currentMeetingId else {
            Logger.log("No active meeting to stop", log: Logger.general)
            return
        }
        
        status = .stopping
        
        // Stop recording - this may add final segments
        _ = await recorder.stopRecording()
        
        // Give a brief moment for any pending segment callbacks to process
        try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
        
        // Stop auto-save
        stopAutoSave()
        
        // Mark meeting as completed immediately (UI can show it)
        // Summary will be generated in the background
        storage.completeMeeting(meetingId)
        
        // Save the live transcript count before resetting
        let segmentCount = liveTranscript.count
        
        // Reset session state immediately so user can interact with the app
        isActive = false
        currentMeetingId = nil
        status = .completed
        liveTranscript = []
        
        Logger.log("Meeting session completed: \(meetingId) with \(segmentCount) segments", log: Logger.general)
        
        // Generate summary in the background (non-blocking)
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            
            // Mark as processing
            await MainActor.run {
                if var meeting = self.storage.getMeeting(meetingId) {
                    meeting.markAsProcessing()
                    self.storage.update(meeting)
                }
            }
            
            // Generate summary (this is the slow part)
            await self.generateMeetingSummary(meetingId: meetingId)
            
            Logger.log("Meeting summary generation completed: \(meetingId)", log: Logger.general)
        }
    }
    
    /// Cancel the current meeting without saving summary
    func cancelMeeting() {
        guard isActive else { return }
        
        recorder.cancelRecording()
        stopAutoSave()
        
        if let meetingId = currentMeetingId {
            storage.delete(meetingId)
        }
        
        isActive = false
        currentMeetingId = nil
        status = .idle
        liveTranscript = []
        errorMessage = nil
        
        Logger.log("Meeting cancelled", log: Logger.general)
    }
    
    /// Pause/Resume recording (not currently supported by recorder)
    func togglePause() {
        // Future implementation
    }
    
    // MARK: - Segment Handling
    
    private func handleNewSegment(_ segment: MeetingSegment, forMeetingId meetingId: UUID) {
        // Add to live transcript (only if still active), sorted by timestamp
        if isActive {
            liveTranscript.append(segment)
            liveTranscript.sort { $0.startTime < $1.startTime }
        }
        
        // Add to storage - always save even if session is ending
        storage.addSegment(segment, to: meetingId)
        
        Logger.log("New segment added to meeting \(meetingId): \(segment.text.prefix(50))...", log: Logger.general)
    }
    
    // MARK: - Summary Generation
    
    private func generateMeetingSummary(meetingId: UUID) async {
        // Get meeting on main actor
        let meeting: MeetingNote? = await MainActor.run {
            storage.getMeeting(meetingId)
        }
        
        guard let meeting = meeting else { return }
        
        // Check if we have transcript to summarize
        guard !meeting.segments.isEmpty else {
            Logger.log("No segments to summarize", log: Logger.general)
            return
        }
        
        do {
            let summary = try await ai.generateSummary(from: meeting)
            
            // Update storage on main actor
            await MainActor.run {
                storage.updateSummary(summary, for: meetingId)
            }
            
            Logger.log("Summary generated for meeting: \(meetingId)", log: Logger.general)
        } catch {
            Logger.log("Failed to generate summary: \(error)", log: Logger.general, type: .error)
            // Meeting will still be completed, just without summary
        }
    }
    
    // MARK: - Auto Detection Handlers
    
    private var autoStopTimer: Timer?
    
    private func handleMeetingAppDetected(source: MeetingSource) {
        guard autoDetectEnabled, !isActive else { return }
        
        Logger.log("Auto-detected meeting app: \(source.rawValue), auto-starting recording", log: Logger.general)
        
        // Cancel any pending auto-stop from a previous detection cycle
        autoStopTimer?.invalidate()
        autoStopTimer = nil
        
        // Auto-start recording
        Task {
            await startMeeting(source: source)
        }
    }
    
    private func handleMeetingAppClosed() {
        guard autoDetectEnabled, isActive else { return }
        
        Logger.log("Meeting app closed, auto-stopping after delay", log: Logger.general)
        
        // Stop after a short delay to avoid false positives (e.g. app briefly hidden)
        autoStopTimer?.invalidate()
        autoStopTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isActive else { return }
                Logger.log("Auto-stop delay elapsed, stopping meeting", log: Logger.general)
                await self.stopMeeting()
                self.autoStopTimer = nil
            }
        }
    }
    
    // MARK: - Error Handling
    
    private func handleRecordingError(_ error: Error) {
        Logger.log("Recording error: \(error)", log: Logger.general, type: .error)
        errorMessage = error.localizedDescription
        
        // Don't stop the session on minor errors, just log
        if case MeetingRecorderError.recordingFailed = error {
            Task {
                await stopMeeting()
            }
        }
    }
    
    // MARK: - Auto Save
    
    private func startAutoSave() {
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.storage.saveMeetings()
            }
        }
    }
    
    private func stopAutoSave() {
        autoSaveTimer?.invalidate()
        autoSaveTimer = nil
        storage.saveMeetings()
    }
    
    // MARK: - Q&A
    
    /// Ask a question about a specific meeting
    func askQuestion(_ question: String, meetingId: UUID) async throws -> MeetingQA {
        guard let meeting = storage.getMeeting(meetingId) else {
            throw MeetingSessionError.meetingNotFound
        }
        
        let answer = try await ai.askQuestion(question: question, meeting: meeting)
        let qa = MeetingQA(question: question, answer: answer)
        
        storage.addQA(qa, to: meetingId)
        
        return qa
    }
    
    // MARK: - Utility
    
    private func generateMeetingTitle(source: MeetingSource) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d, h:mm a"
        let dateStr = dateFormatter.string(from: Date())
        
        return "\(source.rawValue) Meeting - \(dateStr)"
    }
    
    // MARK: - Current Meeting Access
    
    var currentMeeting: MeetingNote? {
        guard let id = currentMeetingId else { return nil }
        return storage.getMeeting(id)
    }
    
    var recordingDuration: TimeInterval {
        recorder.recordingDuration
    }
    
    var formattedDuration: String {
        recorder.formattedDuration
    }
    
    var audioLevel: Float {
        recorder.normalizedLevel
    }
    
    var segmentCount: Int {
        liveTranscript.count
    }
}

// MARK: - Errors

enum MeetingSessionError: LocalizedError {
    case meetingNotFound
    case alreadyActive
    case notActive
    
    var errorDescription: String? {
        switch self {
        case .meetingNotFound:
            return "Meeting not found"
        case .alreadyActive:
            return "A meeting session is already active"
        case .notActive:
            return "No active meeting session"
        }
    }
}
