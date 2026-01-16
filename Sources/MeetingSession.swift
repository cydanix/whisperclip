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
    @Published var autoDetectEnabled: Bool = false {
        didSet {
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
            try await recorder.startRecording(
                onTranscript: { [weak self] segment in
                    Task { @MainActor in
                        self?.handleNewSegment(segment)
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
        
        // Stop recording
        _ = await recorder.stopRecording()
        
        // Stop auto-save
        stopAutoSave()
        
        // Mark meeting as processing
        if var meeting = storage.getMeeting(meetingId) {
            meeting.markAsProcessing()
            storage.update(meeting)
        }
        
        status = .processing
        
        // Generate summary
        await generateMeetingSummary(meetingId: meetingId)
        
        // Complete the meeting
        storage.completeMeeting(meetingId)
        
        isActive = false
        status = .completed
        
        Logger.log("Meeting session completed: \(meetingId)", log: Logger.general)
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
    
    private func handleNewSegment(_ segment: MeetingSegment) {
        guard let meetingId = currentMeetingId else { return }
        
        // Add to live transcript
        liveTranscript.append(segment)
        
        // Add to storage
        storage.addSegment(segment, to: meetingId)
        
        Logger.log("New segment added: \(segment.text.prefix(50))...", log: Logger.general)
    }
    
    // MARK: - Summary Generation
    
    private func generateMeetingSummary(meetingId: UUID) async {
        guard let meeting = storage.getMeeting(meetingId) else { return }
        
        // Check if we have transcript to summarize
        guard !meeting.segments.isEmpty else {
            Logger.log("No segments to summarize", log: Logger.general)
            return
        }
        
        do {
            let summary = try await ai.generateSummary(from: meeting)
            storage.updateSummary(summary, for: meetingId)
            Logger.log("Summary generated for meeting: \(meetingId)", log: Logger.general)
        } catch {
            Logger.log("Failed to generate summary: \(error)", log: Logger.general, type: .error)
            // Meeting will still be completed, just without summary
        }
    }
    
    // MARK: - Auto Detection Handlers
    
    private func handleMeetingAppDetected(source: MeetingSource) {
        guard autoDetectEnabled, !isActive else { return }
        
        Logger.log("Auto-detected meeting app: \(source.rawValue)", log: Logger.general)
        
        // Prompt user or auto-start (could be a setting)
        // For now, just log it - user needs to manually start
        NotificationCenter.default.post(name: .meetingAppDetected, object: source)
    }
    
    private func handleMeetingAppClosed() {
        guard autoDetectEnabled, isActive else { return }
        
        Logger.log("Meeting app closed, considering auto-stop", log: Logger.general)
        
        // Could auto-stop after a delay - for now just notify
        // User should manually stop to ensure proper processing
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
