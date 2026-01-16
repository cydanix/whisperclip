import Foundation

/// Manages persistence of meeting notes
@MainActor
class MeetingStorage: ObservableObject {
    static let shared = MeetingStorage()
    
    private let maxMeetings = 100
    private let storageKey = "meetingNotes"
    
    @Published private(set) var meetings: [MeetingNote] = []
    @Published var currentMeeting: MeetingNote?
    
    private init() {
        loadMeetings()
    }
    
    // MARK: - CRUD Operations
    
    func create(title: String = "New Meeting", source: MeetingSource = .manual) -> MeetingNote {
        let meeting = MeetingNote(title: title, source: source)
        meetings.insert(meeting, at: 0)
        currentMeeting = meeting
        saveMeetings()
        
        NotificationCenter.default.post(name: .meetingStarted, object: meeting)
        Logger.log("Created new meeting: \(meeting.id)", log: Logger.general)
        
        return meeting
    }
    
    func update(_ meeting: MeetingNote) {
        if let index = meetings.firstIndex(where: { $0.id == meeting.id }) {
            meetings[index] = meeting
            
            // Update current meeting if it's the same
            if currentMeeting?.id == meeting.id {
                currentMeeting = meeting
            }
            
            saveMeetings()
        }
    }
    
    func addSegment(_ segment: MeetingSegment, to meetingId: UUID) {
        if let index = meetings.firstIndex(where: { $0.id == meetingId }) {
            meetings[index].addSegment(segment)
            
            if currentMeeting?.id == meetingId {
                currentMeeting = meetings[index]
            }
            
            // Don't save after every segment for performance - batch save periodically
            NotificationCenter.default.post(name: .meetingSegmentAdded, object: segment)
        }
    }
    
    func completeMeeting(_ meetingId: UUID) {
        if let index = meetings.firstIndex(where: { $0.id == meetingId }) {
            meetings[index].complete()
            
            if currentMeeting?.id == meetingId {
                currentMeeting = meetings[index]
            }
            
            saveMeetings()
            NotificationCenter.default.post(name: .meetingEnded, object: meetings[index])
            Logger.log("Completed meeting: \(meetingId)", log: Logger.general)
        }
    }
    
    func updateSummary(_ summary: MeetingSummary, for meetingId: UUID) {
        if let index = meetings.firstIndex(where: { $0.id == meetingId }) {
            meetings[index].summary = summary
            meetings[index].status = .completed
            
            if currentMeeting?.id == meetingId {
                currentMeeting = meetings[index]
            }
            
            saveMeetings()
            NotificationCenter.default.post(name: .meetingSummaryGenerated, object: meetings[index])
        }
    }
    
    func addQA(_ qa: MeetingQA, to meetingId: UUID) {
        if let index = meetings.firstIndex(where: { $0.id == meetingId }) {
            meetings[index].qaHistory.append(qa)
            
            if currentMeeting?.id == meetingId {
                currentMeeting = meetings[index]
            }
            
            saveMeetings()
        }
    }
    
    func toggleFavorite(_ meetingId: UUID) {
        if let index = meetings.firstIndex(where: { $0.id == meetingId }) {
            meetings[index].isFavorite.toggle()
            
            if currentMeeting?.id == meetingId {
                currentMeeting = meetings[index]
            }
            
            saveMeetings()
        }
    }
    
    func delete(_ meetingId: UUID) {
        meetings.removeAll { $0.id == meetingId }
        
        if currentMeeting?.id == meetingId {
            currentMeeting = nil
        }
        
        saveMeetings()
        Logger.log("Deleted meeting: \(meetingId)", log: Logger.general)
    }
    
    func clearAll() {
        meetings.removeAll()
        currentMeeting = nil
        saveMeetings()
        Logger.log("Cleared all meetings", log: Logger.general)
    }
    
    func clearCurrentMeeting() {
        currentMeeting = nil
    }
    
    // MARK: - Queries
    
    func getMeeting(_ id: UUID) -> MeetingNote? {
        meetings.first { $0.id == id }
    }
    
    func getRecentMeetings(limit: Int = 10) -> [MeetingNote] {
        Array(meetings.prefix(limit))
    }
    
    func getFavoriteMeetings() -> [MeetingNote] {
        meetings.filter { $0.isFavorite }
    }
    
    func search(query: String) -> [MeetingNote] {
        guard !query.isEmpty else { return meetings }
        
        let lowercasedQuery = query.lowercased()
        return meetings.filter { meeting in
            meeting.title.lowercased().contains(lowercasedQuery) ||
            meeting.plainTranscript.lowercased().contains(lowercasedQuery) ||
            meeting.summary.brief.lowercased().contains(lowercasedQuery) ||
            meeting.summary.detailed.lowercased().contains(lowercasedQuery) ||
            meeting.tags.contains { $0.lowercased().contains(lowercasedQuery) }
        }
    }
    
    func getMeetingsForDate(_ date: Date) -> [MeetingNote] {
        let calendar = Calendar.current
        return meetings.filter { meeting in
            calendar.isDate(meeting.startedAt, inSameDayAs: date)
        }
    }
    
    // MARK: - Persistence
    
    private func loadMeetings() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do {
            meetings = try JSONDecoder().decode([MeetingNote].self, from: data)
            Logger.log("Loaded \(meetings.count) meetings", log: Logger.general)
        } catch {
            Logger.log("Failed to load meetings: \(error)", log: Logger.general, type: .error)
        }
    }
    
    func saveMeetings() {
        // Trim to max meetings
        if meetings.count > maxMeetings {
            meetings = Array(meetings.prefix(maxMeetings))
        }
        
        do {
            let data = try JSONEncoder().encode(meetings)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            Logger.log("Failed to save meetings: \(error)", log: Logger.general, type: .error)
        }
    }
    
    // MARK: - Export
    
    func exportAsMarkdown(_ meeting: MeetingNote) -> String {
        var md = "# \(meeting.title)\n\n"
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .short
        
        md += "**Date:** \(dateFormatter.string(from: meeting.startedAt))\n"
        md += "**Duration:** \(meeting.formattedDuration)\n"
        md += "**Source:** \(meeting.source.rawValue)\n\n"
        
        if !meeting.summary.brief.isEmpty {
            md += "## Summary\n\n"
            md += "\(meeting.summary.brief)\n\n"
        }
        
        if !meeting.summary.detailed.isEmpty {
            md += "### Details\n\n"
            md += "\(meeting.summary.detailed)\n\n"
        }
        
        if !meeting.summary.topics.isEmpty {
            md += "## Key Topics\n\n"
            for topic in meeting.summary.topics {
                md += "### \(topic.title)\n"
                md += "\(topic.summary)\n\n"
            }
        }
        
        if !meeting.summary.actionItems.isEmpty {
            md += "## Action Items\n\n"
            for item in meeting.summary.actionItems {
                let checkbox = item.isCompleted ? "[x]" : "[ ]"
                var line = "- \(checkbox) \(item.text)"
                if let assignee = item.assignee {
                    line += " (@\(assignee))"
                }
                md += "\(line)\n"
            }
            md += "\n"
        }
        
        if !meeting.summary.decisions.isEmpty {
            md += "## Decisions\n\n"
            for decision in meeting.summary.decisions {
                md += "- \(decision)\n"
            }
            md += "\n"
        }
        
        if !meeting.summary.followUps.isEmpty {
            md += "## Follow-ups\n\n"
            for followUp in meeting.summary.followUps {
                md += "- \(followUp)\n"
            }
            md += "\n"
        }
        
        md += "## Transcript\n\n"
        for segment in meeting.segments {
            md += "**[\(segment.formattedTime)] \(segment.speaker.displayName):** \(segment.text)\n\n"
        }
        
        return md
    }
    
    func exportAsJSON(_ meeting: MeetingNote) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(meeting)
    }
}
