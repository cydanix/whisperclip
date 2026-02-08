import SwiftUI

struct MeetingDetailView: View {
    let meeting: MeetingNote
    
    @ObservedObject private var storage = MeetingStorage.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedTab: DetailTab = .summary
    @State private var questionText = ""
    @State private var isAskingQuestion = false
    @State private var qaError: String?
    @State private var isRegenerating = false
    @State private var showCopiedToast = false
    
    /// Always read the latest meeting data from storage (reactive to @Published changes)
    private var currentMeeting: MeetingNote {
        storage.getMeeting(meeting.id) ?? meeting
    }
    
    enum DetailTab: String, CaseIterable {
        case summary = "Summary"
        case transcript = "Transcript"
        case actions = "Actions"
        case qa = "Q&A"
        
        var icon: String {
            switch self {
            case .summary: return "doc.text"
            case .transcript: return "text.quote"
            case .actions: return "checkmark.circle"
            case .qa: return "questionmark.bubble"
            }
        }
    }
    
    init(meeting: MeetingNote) {
        self.meeting = meeting
    }
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter
    }()
    
    var body: some View {
        ZStack {
            // Background
            Color(red: 0.05, green: 0.05, blue: 0.08)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                headerView
                
                // Tab bar
                tabBar
                
                Divider()
                    .background(Color.white.opacity(0.1))
                
                // Content
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch selectedTab {
                        case .summary:
                            summaryContent
                        case .transcript:
                            transcriptContent
                        case .actions:
                            actionsContent
                        case .qa:
                            qaContent
                        }
                    }
                    .padding(24)
                }
            }
            
            // Copied toast
            if showCopiedToast {
                VStack {
                    Spacer()
                    
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Copied to clipboard")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(10)
                    .padding(.bottom, 20)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .foregroundColor(.white)
        .frame(minWidth: 700, minHeight: 600)
        // currentMeeting is now a computed property that reads directly
        // from storage, so the view is always in sync automatically
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        // Source badge
                        HStack(spacing: 6) {
                            Image(systemName: currentMeeting.source.icon)
                                .font(.system(size: 12))
                            Text(currentMeeting.source.rawValue)
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(6)
                        
                        // Status badge
                        HStack(spacing: 4) {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 6, height: 6)
                            Text(currentMeeting.status.rawValue)
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(statusColor.opacity(0.15))
                        .cornerRadius(6)
                    }
                    
                    Text(currentMeeting.title)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    
                    HStack(spacing: 16) {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .font(.system(size: 12))
                            Text(dateFormatter.string(from: currentMeeting.startedAt))
                                .font(.system(size: 13))
                        }
                        .foregroundColor(.gray)
                        
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 12))
                            Text(currentMeeting.formattedDuration)
                                .font(.system(size: 13))
                        }
                        .foregroundColor(.gray)
                        
                        HStack(spacing: 4) {
                            Image(systemName: "text.bubble")
                                .font(.system(size: 12))
                            Text("\(currentMeeting.segments.count) segments")
                                .font(.system(size: 13))
                        }
                        .foregroundColor(.gray)
                    }
                }
                
                Spacer()
                
                HStack(spacing: 12) {
                    // Favorite button
                    Button {
                        storage.toggleFavorite(meeting.id)
                    } label: {
                        Image(systemName: currentMeeting.isFavorite ? "star.fill" : "star")
                            .font(.system(size: 16))
                            .foregroundColor(currentMeeting.isFavorite ? .yellow : .gray)
                    }
                    .buttonStyle(.plain)
                    
                    // Export menu
                    Menu {
                        Button {
                            let markdown = storage.exportAsMarkdown(currentMeeting)
                            GenericHelper.copyToClipboard(text: markdown)
                            showCopiedFeedback()
                        } label: {
                            Label("Copy as Markdown", systemImage: "doc.on.doc")
                        }
                        
                        Button {
                            GenericHelper.copyToClipboard(text: currentMeeting.fullTranscript)
                            showCopiedFeedback()
                        } label: {
                            Label("Copy Transcript", systemImage: "text.quote")
                        }
                        
                        if !currentMeeting.summary.brief.isEmpty {
                            Button {
                                GenericHelper.copyToClipboard(text: currentMeeting.summary.detailed)
                                showCopiedFeedback()
                            } label: {
                                Label("Copy Summary", systemImage: "doc.text")
                            }
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16))
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                    
                    // Close button
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.gray)
                            .padding(8)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(24)
        .background(Color.black.opacity(0.3))
    }
    
    private var statusColor: Color {
        switch currentMeeting.status {
        case .scheduled: return .blue
        case .inProgress: return .red
        case .processing: return .orange
        case .completed: return .green
        case .failed: return .red
        }
    }
    
    // MARK: - Tab Bar
    
    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(DetailTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 14))
                            Text(tab.rawValue)
                                .font(.system(size: 14, weight: selectedTab == tab ? .semibold : .medium))
                        }
                        .foregroundColor(selectedTab == tab ? .teal : .gray)
                        
                        Rectangle()
                            .fill(selectedTab == tab ? Color.teal : Color.clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 24)
        .background(Color.black.opacity(0.2))
    }
    
    // MARK: - Summary Content
    
    private var summaryContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            if currentMeeting.summary.isEmpty {
                emptyStateCard(
                    icon: "sparkles",
                    title: "No Summary Yet",
                    message: "AI summary will appear here once the meeting is processed"
                )
                
                if currentMeeting.status == .completed && !currentMeeting.segments.isEmpty {
                    Button {
                        regenerateSummary()
                    } label: {
                        HStack(spacing: 8) {
                            if isRegenerating {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(.white)
                            } else {
                                Image(systemName: "sparkles")
                            }
                            Text(isRegenerating ? "Generating..." : "Generate Summary")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.teal)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    .disabled(isRegenerating)
                }
            } else {
                // Brief summary
                summarySection(title: "Overview", icon: "doc.text.fill") {
                    Text(currentMeeting.summary.brief)
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.9))
                        .lineSpacing(4)
                }
                
                // Detailed summary
                if !currentMeeting.summary.detailed.isEmpty {
                    summarySection(title: "Details", icon: "text.alignleft") {
                        Text(currentMeeting.summary.detailed)
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.8))
                            .lineSpacing(4)
                    }
                }
                
                // Key topics
                if !currentMeeting.summary.topics.isEmpty {
                    summarySection(title: "Key Topics", icon: "list.bullet") {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(currentMeeting.summary.topics) { topic in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(topic.title)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.teal)
                                    
                                    Text(topic.summary)
                                        .font(.system(size: 13))
                                        .foregroundColor(.white.opacity(0.7))
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.white.opacity(0.04))
                                .cornerRadius(8)
                            }
                        }
                    }
                }
                
                // Decisions
                if !currentMeeting.summary.decisions.isEmpty {
                    summarySection(title: "Decisions Made", icon: "arrow.triangle.branch") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(currentMeeting.summary.decisions.indices, id: \.self) { index in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(.green)
                                    
                                    Text(currentMeeting.summary.decisions[index])
                                        .font(.system(size: 14))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                            }
                        }
                    }
                }
                
                // Follow-ups
                if !currentMeeting.summary.followUps.isEmpty {
                    summarySection(title: "Follow-ups", icon: "arrow.right.circle") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(currentMeeting.summary.followUps.indices, id: \.self) { index in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "arrow.right.circle")
                                        .font(.system(size: 14))
                                        .foregroundColor(.blue)
                                    
                                    Text(currentMeeting.summary.followUps[index])
                                        .font(.system(size: 14))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func summarySection<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(.teal)
                
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
            }
            
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04))
        .cornerRadius(12)
    }
    
    // MARK: - Transcript Content
    
    private var transcriptContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if currentMeeting.segments.isEmpty {
                emptyStateCard(
                    icon: "text.quote",
                    title: "No Transcript",
                    message: "Meeting transcript will appear here"
                )
            } else {
                // Speaker stats
                speakerStatsView
                
                // Transcript
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(currentMeeting.segments) { segment in
                        TranscriptSegmentRow(segment: segment)
                    }
                }
            }
        }
    }
    
    private var speakerStatsView: some View {
        HStack(spacing: 16) {
            ForEach(Array(currentMeeting.speakerStats.keys), id: \.self) { speaker in
                if let stats = currentMeeting.speakerStats[speaker] {
                    HStack(spacing: 8) {
                        Image(systemName: speaker.icon)
                            .font(.system(size: 12))
                            .foregroundColor(speakerColor(speaker))
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(speaker.displayName)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                            
                            Text("\(stats.count) segments")
                                .font(.system(size: 11))
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(speakerColor(speaker).opacity(0.15))
                    .cornerRadius(8)
                }
            }
        }
        .padding(.bottom, 8)
    }
    
    private func speakerColor(_ speaker: Speaker) -> Color {
        switch speaker {
        case .me: return .blue
        case .other: return .purple
        case .unknown: return .gray
        }
    }
    
    // MARK: - Actions Content
    
    private var actionsContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            if currentMeeting.summary.actionItems.isEmpty {
                emptyStateCard(
                    icon: "checkmark.circle",
                    title: "No Action Items",
                    message: "Action items extracted from the meeting will appear here"
                )
            } else {
                ForEach(currentMeeting.summary.actionItems) { item in
                    ActionItemRow(item: item)
                }
            }
        }
    }
    
    // MARK: - Q&A Content
    
    private var qaContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Question input
            VStack(alignment: .leading, spacing: 8) {
                Text("Ask a question about this meeting")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.gray)
                
                HStack(spacing: 12) {
                    TextField("What was discussed about...", text: $questionText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .padding(12)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(10)
                    
                    Button {
                        askQuestion()
                    } label: {
                        if isAskingQuestion {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.white)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 14))
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Color.teal)
                    .cornerRadius(10)
                    .disabled(questionText.isEmpty || isAskingQuestion)
                    .opacity(questionText.isEmpty ? 0.5 : 1)
                }
                
                if let error = qaError {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                }
            }
            .padding(16)
            .background(Color.white.opacity(0.04))
            .cornerRadius(12)
            
            // Q&A history
            if currentMeeting.qaHistory.isEmpty {
                emptyStateCard(
                    icon: "questionmark.bubble",
                    title: "No Questions Yet",
                    message: "Ask questions about the meeting to get AI-powered answers"
                )
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Previous Questions")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                    
                    ForEach(currentMeeting.qaHistory.reversed()) { qa in
                        QARow(qa: qa)
                    }
                }
            }
        }
    }
    
    // MARK: - Empty State
    
    private func emptyStateCard(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .light))
                .foregroundColor(.gray.opacity(0.5))
            
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                
                Text(message)
                    .font(.system(size: 13))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(Color.white.opacity(0.04))
        .cornerRadius(12)
    }
    
    // MARK: - Actions
    
    private func askQuestion() {
        guard !questionText.isEmpty else { return }
        
        isAskingQuestion = true
        qaError = nil
        
        let question = questionText
        questionText = ""
        let meetingId = meeting.id
        
        Task {
            do {
                _ = try await MeetingSession.shared.askQuestion(question, meetingId: meetingId)
                
                // No need to manually update currentMeeting — it's a computed
                // property that reads from storage, and storage.addQA already
                // updated the @Published meetings array. The view re-renders
                // automatically via @ObservedObject.
                await MainActor.run {
                    isAskingQuestion = false
                }
            } catch {
                await MainActor.run {
                    qaError = error.localizedDescription
                    questionText = question // Restore question
                    isAskingQuestion = false
                }
            }
        }
    }
    
    private func regenerateSummary() {
        isRegenerating = true
        let meetingId = meeting.id
        
        Task {
            do {
                let summary = try await MeetingAI.shared.generateSummary(from: currentMeeting)
                
                await MainActor.run {
                    storage.updateSummary(summary, for: meetingId)
                    // currentMeeting is computed from storage — auto-updates
                    isRegenerating = false
                }
            } catch {
                await MainActor.run {
                    isRegenerating = false
                }
            }
        }
    }
    
    private func showCopiedFeedback() {
        withAnimation {
            showCopiedToast = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showCopiedToast = false
            }
        }
    }
}

// MARK: - Supporting Views

struct TranscriptSegmentRow: View {
    let segment: MeetingSegment
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Time
            Text(segment.formattedTime)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.gray)
                .frame(width: 40)
            
            // Speaker badge
            Text(segment.speaker.displayName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(speakerColor)
                .frame(width: 50)
            
            // Text
            Text(segment.text)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.9))
                .textSelection(.enabled)
        }
        .padding(12)
        .background(Color.white.opacity(0.02))
        .cornerRadius(8)
    }
    
    private var speakerColor: Color {
        switch segment.speaker {
        case .me: return .blue
        case .other: return .purple
        case .unknown: return .gray
        }
    }
}

struct ActionItemRow: View {
    let item: ActionItem
    @State private var isChecked: Bool
    
    init(item: ActionItem) {
        self.item = item
        self._isChecked = State(initialValue: item.isCompleted)
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                isChecked.toggle()
            } label: {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(isChecked ? .green : .gray)
            }
            .buttonStyle(.plain)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(item.text)
                    .font(.system(size: 14))
                    .foregroundColor(isChecked ? .gray : .white)
                    .strikethrough(isChecked)
                
                if let assignee = item.assignee {
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 10))
                        Text(assignee)
                            .font(.system(size: 12))
                    }
                    .foregroundColor(.orange)
                }
            }
            
            Spacer()
        }
        .padding(12)
        .background(Color.white.opacity(0.04))
        .cornerRadius(10)
    }
}

struct QARow: View {
    let qa: MeetingQA
    
    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Question
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.teal)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(qa.question)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                    
                    Text(timeFormatter.string(from: qa.askedAt))
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
            }
            
            // Answer
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16))
                    .foregroundColor(.orange)
                
                Text(qa.answer)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.85))
                    .textSelection(.enabled)
            }
            .padding(12)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)
        }
        .padding(16)
        .background(Color.white.opacity(0.04))
        .cornerRadius(12)
    }
}
