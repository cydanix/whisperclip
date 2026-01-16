import SwiftUI

struct MeetingNotesView: View {
    @ObservedObject private var session = MeetingSession.shared
    @ObservedObject private var storage = MeetingStorage.shared
    @ObservedObject private var detector = MeetingDetector.shared
    @ObservedObject private var recorder = MeetingRecorder.shared
    
    @State private var selectedMeeting: MeetingNote?
    @State private var searchText = ""
    @State private var showingClearConfirmation = false
    @State private var pulseAnimation = false
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.06, blue: 0.1),
                    Color(red: 0.06, green: 0.04, blue: 0.12),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            if session.isActive {
                activeMeetingView
            } else {
                meetingListView
            }
        }
        .foregroundColor(.white)
        .sheet(item: $selectedMeeting) { meeting in
            MeetingDetailView(meeting: meeting)
        }
        .alert("Clear All Meetings", isPresented: $showingClearConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear All", role: .destructive) {
                storage.clearAll()
            }
        } message: {
            Text("Are you sure you want to delete all meeting notes? This action cannot be undone.")
        }
    }
    
    // MARK: - Active Meeting View
    
    private var activeMeetingView: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recording Meeting")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                        
                        if let meeting = session.currentMeeting {
                            Text(meeting.title)
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                        }
                    }
                    
                    Spacer()
                    
                    // Recording indicator
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 12, height: 12)
                            .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulseAnimation)
                        
                        Text(session.formattedDuration)
                            .font(.system(size: 16, weight: .medium, design: .monospaced))
                            .foregroundColor(.red)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.15))
                    .cornerRadius(8)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                
                // Audio level visualization with waveform
                MeetingWaveformView(recorder: recorder)
                    .frame(height: 60)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
            }
            
            Divider()
                .background(Color.white.opacity(0.1))
                .padding(.top, 16)
            
            // Live transcript
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(session.liveTranscript) { segment in
                            LiveSegmentRow(segment: segment)
                                .id(segment.id)
                        }
                        
                        if session.liveTranscript.isEmpty {
                            VStack(spacing: 12) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Listening for speech...")
                                    .font(.system(size: 14))
                                    .foregroundColor(.gray)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        }
                    }
                    .padding(16)
                }
                .onChange(of: session.liveTranscript.count) { _, _ in
                    if let lastSegment = session.liveTranscript.last {
                        withAnimation {
                            proxy.scrollTo(lastSegment.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            // Control buttons
            HStack(spacing: 16) {
                Button {
                    session.cancelMeeting()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14))
                        Text("Cancel")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                
                Button {
                    Task {
                        await session.stopMeeting()
                    }
                } label: {
                    HStack(spacing: 8) {
                        if session.status == .stopping || session.status == .processing {
                            ProgressView()
                                .scaleEffect(0.7)
                                .tint(.white)
                        } else {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 14))
                        }
                        Text(session.status == .processing ? "Processing..." : "End Meeting")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [.green, .green.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .disabled(session.status == .stopping || session.status == .processing)
            }
            .padding(16)
        }
        .onAppear {
            pulseAnimation = true
        }
        .onDisappear {
            pulseAnimation = false
        }
    }
    
    // MARK: - Meeting List View
    
    private var meetingListView: some View {
        VStack(spacing: 0) {
            // Header with new meeting button
            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Meeting Notes")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                        
                        Text("AI-powered meeting summaries")
                            .font(.system(size: 13))
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                    
                    if !storage.meetings.isEmpty {
                        Button {
                            showingClearConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 14))
                                .foregroundColor(.red.opacity(0.8))
                                .padding(8)
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                // New meeting button
                newMeetingButton
                
                // Detection status
                if detector.isDetectionEnabled {
                    detectionStatusBanner
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            if storage.meetings.isEmpty {
                emptyStateView
            } else {
                // Search bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                    
                    TextField("Search meetings...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                    
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.06))
                .cornerRadius(10)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                
                // Meeting list
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredMeetings) { meeting in
                            MeetingListRow(meeting: meeting, dateFormatter: dateFormatter)
                                .onTapGesture {
                                    selectedMeeting = meeting
                                }
                                .contextMenu {
                                    Button {
                                        GenericHelper.copyToClipboard(text: MeetingStorage.shared.exportAsMarkdown(meeting))
                                    } label: {
                                        Label("Copy as Markdown", systemImage: "doc.on.doc")
                                    }
                                    
                                    Button {
                                        storage.toggleFavorite(meeting.id)
                                    } label: {
                                        Label(
                                            meeting.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                                            systemImage: meeting.isFavorite ? "star.slash" : "star"
                                        )
                                    }
                                    
                                    Divider()
                                    
                                    Button(role: .destructive) {
                                        storage.delete(meeting.id)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
        }
    }
    
    private var newMeetingButton: some View {
        Button {
            Task {
                await session.startMeeting()
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.teal.opacity(0.2))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.teal)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Start New Meeting")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text("Record and transcribe with AI")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.gray)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [Color.teal.opacity(0.15), Color.teal.opacity(0.05)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.teal.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    private var detectionStatusBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: detector.isMeetingActive ? "video.fill" : "eye.fill")
                .font(.system(size: 14))
                .foregroundColor(detector.isMeetingActive ? .green : .blue)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(detector.isMeetingActive ? "Meeting Detected" : "Auto-Detection Active")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                
                if let source = detector.detectedSource {
                    Text(source.rawValue)
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                } else {
                    Text("Monitoring for Zoom, Teams, Meet...")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
            }
            
            Spacer()
            
            Toggle("", isOn: $session.autoDetectEnabled)
                .toggleStyle(.switch)
                .scaleEffect(0.8)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.blue.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.teal.opacity(0.1))
                    .frame(width: 120, height: 120)
                
                Circle()
                    .stroke(Color.teal.opacity(0.2), lineWidth: 2)
                    .frame(width: 120, height: 120)
                
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 50, weight: .light))
                    .foregroundColor(.teal.opacity(0.6))
            }
            
            VStack(spacing: 8) {
                Text("No Meeting Notes Yet")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                
                Text("Start a meeting to capture and summarize\nyour conversations with AI")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
        }
        .padding(.horizontal, 40)
    }
    
    private var filteredMeetings: [MeetingNote] {
        if searchText.isEmpty {
            return storage.meetings
        }
        return storage.search(query: searchText)
    }
}

// MARK: - Supporting Views

struct LiveSegmentRow: View {
    let segment: MeetingSegment
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Speaker icon
            ZStack {
                Circle()
                    .fill(speakerColor.opacity(0.2))
                    .frame(width: 32, height: 32)
                
                Image(systemName: segment.speaker.icon)
                    .font(.system(size: 12))
                    .foregroundColor(speakerColor)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(segment.speaker.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(speakerColor)
                    
                    Text(segment.formattedTime)
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
                
                Text(segment.text)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.9))
            }
            
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.04))
        )
    }
    
    private var speakerColor: Color {
        switch segment.speaker {
        case .me: return .blue
        case .other: return .purple
        case .unknown: return .gray
        }
    }
}

struct MeetingListRow: View {
    let meeting: MeetingNote
    let dateFormatter: DateFormatter
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                // Source icon
                ZStack {
                    Circle()
                        .fill(sourceColor.opacity(0.15))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: meeting.source.icon)
                        .font(.system(size: 16))
                        .foregroundColor(sourceColor)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(meeting.title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        if meeting.isFavorite {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.yellow)
                        }
                    }
                    
                    HStack(spacing: 8) {
                        Text(dateFormatter.string(from: meeting.startedAt))
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                        
                        Text("•")
                            .foregroundColor(.gray.opacity(0.5))
                        
                        Text(meeting.formattedDuration)
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                        
                        if !meeting.summary.isEmpty {
                            Text("•")
                                .foregroundColor(.gray.opacity(0.5))
                            
                            Image(systemName: "sparkles")
                                .font(.system(size: 10))
                                .foregroundColor(.teal)
                        }
                    }
                }
                
                Spacer()
                
                // Status badge
                statusBadge
            }
            
            // Summary preview
            if !meeting.summary.brief.isEmpty {
                Text(meeting.summary.brief)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(2)
            } else if meeting.status == .completed && meeting.segments.isEmpty == false {
                Text(meeting.segments.first?.text ?? "")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(2)
            }
            
            // Quick stats
            if meeting.status == .completed && !meeting.summary.actionItems.isEmpty {
                HStack(spacing: 16) {
                    statBadge(icon: "checkmark.circle", text: "\(meeting.summary.actionItems.count) action items", color: .orange)
                    
                    if !meeting.summary.decisions.isEmpty {
                        statBadge(icon: "arrow.triangle.branch", text: "\(meeting.summary.decisions.count) decisions", color: .green)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(isHovered ? 0.08 : 0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
    
    private var sourceColor: Color {
        switch meeting.source {
        case .zoom: return .blue
        case .teams: return .purple
        case .meet: return .green
        case .webex: return .orange
        case .slack: return .pink
        case .discord: return .indigo
        case .facetime: return .green
        case .manual: return .teal
        case .unknown: return .gray
        }
    }
    
    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            
            Text(meeting.status.rawValue)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(statusColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.15))
        .cornerRadius(6)
    }
    
    private var statusColor: Color {
        switch meeting.status {
        case .scheduled: return .blue
        case .inProgress: return .red
        case .processing: return .orange
        case .completed: return .green
        case .failed: return .red
        }
    }
    
    private func statBadge(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(color)
            
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(.gray)
        }
    }
}
