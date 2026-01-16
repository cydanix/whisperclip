import SwiftUI

/// Animated waveform visualization for meeting recording
struct MeetingWaveformView: View {
    @ObservedObject var recorder: MeetingRecorder
    
    @State private var levels: [Float] = Array(repeating: 0, count: 50)
    private let maxSamples = 50
    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 3) {
                ForEach(0..<maxSamples, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barGradient(for: index))
                        .frame(width: barWidth(geo: geo), height: barHeight(for: index, in: geo))
                        .animation(.easeOut(duration: 0.1), value: levels[index])
                }
            }
            .frame(maxHeight: .infinity)
        }
        .onReceive(timer) { _ in
            updateLevels()
        }
    }
    
    private func barWidth(geo: GeometryProxy) -> CGFloat {
        let totalSpacing = CGFloat(maxSamples - 1) * 3
        return (geo.size.width - totalSpacing) / CGFloat(maxSamples)
    }
    
    private func barHeight(for index: Int, in geo: GeometryProxy) -> CGFloat {
        let level = levels[index]
        let minHeight: CGFloat = 4
        let maxHeight = geo.size.height
        let normalizedLevel = CGFloat(level)
        return max(minHeight, normalizedLevel * maxHeight)
    }
    
    private func barGradient(for index: Int) -> LinearGradient {
        let level = levels[index]
        
        let colors: [Color]
        if level > 0.7 {
            colors = [.red, .orange]
        } else if level > 0.4 {
            colors = [.orange, .yellow]
        } else {
            colors = [.teal, .cyan]
        }
        
        return LinearGradient(
            colors: colors,
            startPoint: .bottom,
            endPoint: .top
        )
    }
    
    private func updateLevels() {
        guard recorder.isRecording else {
            // Reset to minimal wave when not recording
            withAnimation {
                levels = (0..<maxSamples).map { i in
                    Float(sin(Double(i) * 0.3)) * 0.1 + 0.1
                }
            }
            return
        }
        
        // Add new level and shift
        let newLevel = recorder.normalizedLevel
        levels.append(newLevel)
        if levels.count > maxSamples {
            levels.removeFirst()
        }
    }
}

/// Simple circular audio level indicator
struct AudioLevelIndicator: View {
    let level: Float
    let isActive: Bool
    
    @State private var pulseAnimation = false
    
    var body: some View {
        ZStack {
            // Outer pulse rings when active
            if isActive {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .stroke(Color.teal.opacity(0.3 - Double(i) * 0.1), lineWidth: 2)
                        .frame(width: 80 + CGFloat(i) * 20, height: 80 + CGFloat(i) * 20)
                        .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                        .opacity(pulseAnimation ? 0.0 : 0.6)
                        .animation(
                            .easeInOut(duration: 1.5)
                            .repeatForever(autoreverses: false)
                            .delay(Double(i) * 0.3),
                            value: pulseAnimation
                        )
                }
            }
            
            // Background circle
            Circle()
                .fill(Color.teal.opacity(0.1))
                .frame(width: 70, height: 70)
            
            // Level indicator
            Circle()
                .fill(
                    LinearGradient(
                        colors: levelColors,
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .frame(width: 60 * CGFloat(max(0.2, level)), height: 60 * CGFloat(max(0.2, level)))
                .animation(.easeOut(duration: 0.1), value: level)
            
            // Mic icon
            Image(systemName: isActive ? "waveform" : "mic.fill")
                .font(.system(size: isActive ? 24 : 20, weight: .semibold))
                .foregroundColor(.white)
                .animation(.easeInOut, value: isActive)
        }
        .onAppear {
            if isActive {
                pulseAnimation = true
            }
        }
        .onChange(of: isActive) { _, newValue in
            pulseAnimation = newValue
        }
    }
    
    private var levelColors: [Color] {
        if level > 0.7 {
            return [.red, .orange]
        } else if level > 0.4 {
            return [.orange, .yellow]
        } else {
            return [.teal, .cyan]
        }
    }
}

/// Meeting status indicator badge
struct MeetingStatusBadge: View {
    let status: MeetingSession.SessionStatus
    
    var body: some View {
        HStack(spacing: 6) {
            if status.isActive {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .modifier(PulseModifier(isAnimating: status == .recording))
            }
            
            Text(status.rawValue)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(statusColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(statusColor.opacity(0.15))
        .cornerRadius(8)
    }
    
    private var statusColor: Color {
        switch status {
        case .idle: return .gray
        case .starting: return .blue
        case .recording: return .red
        case .stopping: return .orange
        case .processing: return .orange
        case .completed: return .green
        case .failed: return .red
        }
    }
}

/// Pulse animation modifier
struct PulseModifier: ViewModifier {
    let isAnimating: Bool
    @State private var scale: CGFloat = 1.0
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onChange(of: isAnimating) { _, newValue in
                if newValue {
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                        scale = 1.3
                    }
                } else {
                    withAnimation {
                        scale = 1.0
                    }
                }
            }
            .onAppear {
                if isAnimating {
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                        scale = 1.3
                    }
                }
            }
    }
}

/// Speaker indicator for live transcript
struct SpeakerBadge: View {
    let speaker: Speaker
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: speaker.icon)
                .font(.system(size: 10))
            Text(speaker.displayName)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(speakerColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(speakerColor.opacity(0.15))
        .cornerRadius(6)
    }
    
    private var speakerColor: Color {
        switch speaker {
        case .me: return .blue
        case .other: return .purple
        case .unknown: return .gray
        }
    }
}

/// Meeting duration timer view
struct MeetingTimerView: View {
    let startTime: Date
    
    @State private var elapsedTime: TimeInterval = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock")
                .font(.system(size: 12))
            Text(formattedTime)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
        }
        .foregroundColor(.white)
        .onReceive(timer) { _ in
            elapsedTime = Date().timeIntervalSince(startTime)
        }
        .onAppear {
            elapsedTime = Date().timeIntervalSince(startTime)
        }
    }
    
    private var formattedTime: String {
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
