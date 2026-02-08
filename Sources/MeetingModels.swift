import Foundation

/// Represents a speaker in a meeting
/// Distinguished by audio source: microphone (Me) vs system audio (Other)
enum Speaker: String, Codable, CaseIterable {
    case me = "Me"
    case other = "Other"
    case unknown = "Unknown"
    
    var displayName: String { rawValue }
    
    var icon: String {
        switch self {
        case .me: return "person.fill"
        case .other: return "person.2.fill"
        case .unknown: return "questionmark.circle"
        }
    }
}

/// A single segment of transcription with speaker info
struct MeetingSegment: Identifiable, Codable, Hashable {
    let id: UUID
    let speaker: Speaker
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let confidence: Float
    
    init(speaker: Speaker, text: String, startTime: TimeInterval, endTime: TimeInterval, confidence: Float = 1.0) {
        self.id = UUID()
        self.speaker = speaker
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
    }
    
    var duration: TimeInterval {
        endTime - startTime
    }
    
    var formattedTime: String {
        let minutes = Int(startTime) / 60
        let seconds = Int(startTime) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

/// An action item extracted from the meeting
struct ActionItem: Identifiable, Codable, Hashable {
    let id: UUID
    var text: String
    var assignee: String?
    var dueDate: Date?
    var isCompleted: Bool
    let createdAt: Date
    
    init(text: String, assignee: String? = nil, dueDate: Date? = nil) {
        self.id = UUID()
        self.text = text
        self.assignee = assignee
        self.dueDate = dueDate
        self.isCompleted = false
        self.createdAt = Date()
    }
}

/// Key topic discussed in the meeting
struct MeetingTopic: Identifiable, Codable, Hashable {
    let id: UUID
    let title: String
    let summary: String
    let relevantSegmentIds: [UUID]
    
    init(title: String, summary: String, relevantSegmentIds: [UUID] = []) {
        self.id = UUID()
        self.title = title
        self.summary = summary
        self.relevantSegmentIds = relevantSegmentIds
    }
}

/// AI-generated summary of the meeting
struct MeetingSummary: Codable, Hashable {
    var brief: String           // 1-2 sentence overview
    var detailed: String        // Full summary
    var topics: [MeetingTopic]  // Key topics discussed
    var actionItems: [ActionItem]
    var decisions: [String]     // Key decisions made
    var followUps: [String]     // Follow-up items
    var generatedAt: Date
    
    init() {
        self.brief = ""
        self.detailed = ""
        self.topics = []
        self.actionItems = []
        self.decisions = []
        self.followUps = []
        self.generatedAt = Date()
    }
    
    var isEmpty: Bool {
        brief.isEmpty && detailed.isEmpty && topics.isEmpty && actionItems.isEmpty
    }
}

/// Q&A entry for post-meeting queries
struct MeetingQA: Identifiable, Codable, Hashable {
    let id: UUID
    let question: String
    let answer: String
    let askedAt: Date
    
    init(question: String, answer: String) {
        self.id = UUID()
        self.question = question
        self.answer = answer
        self.askedAt = Date()
    }
}

/// Meeting status
enum MeetingStatus: String, Codable {
    case scheduled = "Scheduled"
    case inProgress = "In Progress"
    case processing = "Processing"
    case completed = "Completed"
    case failed = "Failed"
    
    var icon: String {
        switch self {
        case .scheduled: return "calendar"
        case .inProgress: return "record.circle"
        case .processing: return "gearshape.2"
        case .completed: return "checkmark.circle"
        case .failed: return "exclamationmark.circle"
        }
    }
    
    var color: String {
        switch self {
        case .scheduled: return "blue"
        case .inProgress: return "red"
        case .processing: return "orange"
        case .completed: return "green"
        case .failed: return "red"
        }
    }
}

/// Detected meeting app source
enum MeetingSource: String, Codable, CaseIterable {
    case zoom = "Zoom"
    case teams = "Microsoft Teams"
    case meet = "Google Meet"
    case webex = "Webex"
    case slack = "Slack"
    case discord = "Discord"
    case facetime = "FaceTime"
    case manual = "Manual"
    case unknown = "Unknown"
    
    var icon: String {
        switch self {
        case .zoom: return "video.fill"
        case .teams: return "person.3.fill"
        case .meet: return "video.badge.checkmark"
        case .webex: return "video.circle"
        case .slack: return "bubble.left.and.bubble.right.fill"
        case .discord: return "headphones"
        case .facetime: return "video.badge.waveform"
        case .manual: return "hand.raised.fill"
        case .unknown: return "questionmark.video"
        }
    }
    
    var bundleIdentifiers: [String] {
        switch self {
        case .zoom: return ["us.zoom.xos", "zoom.us"]
        case .teams: return ["com.microsoft.teams", "com.microsoft.teams2"]
        case .meet: return ["com.google.Chrome", "com.apple.Safari", "com.google.meet"]
        case .webex: return ["com.cisco.webex", "Cisco-Systems.Spark"]
        case .slack: return ["com.tinyspeck.slackmacgap"]
        case .discord: return ["com.hnc.Discord"]
        case .facetime: return ["com.apple.FaceTime"]
        case .manual: return []
        case .unknown: return []
        }
    }
    
    var windowTitleKeywords: [String] {
        switch self {
        case .zoom: return ["Zoom Meeting", "Zoom Webinar", "zoom share", "meeting controls"]
        case .teams: return ["Meeting with", "Call with", "Microsoft Teams call", "Microsoft Teams meeting"]
        case .meet: return ["Google Meet", "meet.google.com"]
        case .webex: return ["Webex Meeting", "Webex"]
        case .slack: return ["Huddle", "Slack call"]
        case .discord: return ["Voice Channel", "Voice Connected"]
        case .facetime: return ["FaceTime"]
        case .manual: return []
        case .unknown: return []
        }
    }
    
    /// Window title patterns that indicate the app is open but NOT in a meeting
    var nonMeetingWindowKeywords: [String] {
        switch self {
        case .zoom: return []
        case .teams: return []
        case .meet: return []
        case .webex: return []
        case .slack: return []
        case .discord: return []
        case .facetime: return []
        case .manual: return []
        case .unknown: return []
        }
    }
}

/// Full meeting note document
struct MeetingNote: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var source: MeetingSource
    var status: MeetingStatus
    var startedAt: Date
    var endedAt: Date?
    var duration: TimeInterval {
        guard let end = endedAt else {
            return Date().timeIntervalSince(startedAt)
        }
        return end.timeIntervalSince(startedAt)
    }
    var segments: [MeetingSegment]
    var summary: MeetingSummary
    var qaHistory: [MeetingQA]
    var isFavorite: Bool
    var tags: [String]
    
    init(title: String = "New Meeting", source: MeetingSource = .manual) {
        self.id = UUID()
        self.title = title
        self.source = source
        self.status = .inProgress
        self.startedAt = Date()
        self.endedAt = nil
        self.segments = []
        self.summary = MeetingSummary()
        self.qaHistory = []
        self.isFavorite = false
        self.tags = []
    }
    
    var fullTranscript: String {
        segments.sorted { $0.startTime < $1.startTime }.map { segment in
            "[\(segment.formattedTime)] \(segment.speaker.displayName): \(segment.text)"
        }.joined(separator: "\n")
    }
    
    var plainTranscript: String {
        segments.sorted { $0.startTime < $1.startTime }.map { $0.text }.joined(separator: " ")
    }
    
    var formattedDuration: String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    var speakerStats: [Speaker: (count: Int, duration: TimeInterval)] {
        var stats: [Speaker: (count: Int, duration: TimeInterval)] = [:]
        for segment in segments {
            let current = stats[segment.speaker] ?? (0, 0)
            stats[segment.speaker] = (current.count + 1, current.duration + segment.duration)
        }
        return stats
    }
    
    mutating func addSegment(_ segment: MeetingSegment) {
        // Insert in chronological order by startTime
        if let index = segments.firstIndex(where: { $0.startTime > segment.startTime }) {
            segments.insert(segment, at: index)
        } else {
            segments.append(segment)
        }
    }
    
    mutating func complete() {
        endedAt = Date()
        status = .completed
    }
    
    mutating func markAsProcessing() {
        status = .processing
    }
    
    mutating func markAsFailed() {
        status = .failed
    }
    
}

/// Notification names for meeting events
extension Notification.Name {
    static let meetingStarted = Notification.Name("MeetingStarted")
    static let meetingEnded = Notification.Name("MeetingEnded")
    static let meetingSegmentAdded = Notification.Name("MeetingSegmentAdded")
    static let meetingSummaryGenerated = Notification.Name("MeetingSummaryGenerated")
    static let meetingAppDetected = Notification.Name("MeetingAppDetected")
    static let meetingAppClosed = Notification.Name("MeetingAppClosed")
}
