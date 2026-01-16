import SwiftUI
import AppKit

enum SidebarItem: String, CaseIterable, Identifiable {
    case microphone = "Microphone"
    case file = "Audio File"
    case meetings = "Meetings"
    case history = "History"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .microphone: return "mic.fill"
        case .file: return "doc.fill.badge.plus"
        case .meetings: return "text.bubble.fill"
        case .history: return "clock.arrow.circlepath"
        }
    }
    
    var color: Color {
        switch self {
        case .microphone: return .red
        case .file: return .blue
        case .meetings: return .teal
        case .history: return .purple
        }
    }
    
    var description: String {
        switch self {
        case .microphone: return "Record voice"
        case .file: return "Import audio"
        case .meetings: return "AI meeting notes"
        case .history: return "Past transcriptions"
        }
    }
}

struct ContentView: View {
    @State private var selectedItem: SidebarItem = .microphone
    @State private var hoveredItem: SidebarItem? = nil
    @ObservedObject private var settings = SettingsStore.shared
    
    private var hotkeyString: String {
        guard settings.hotkeyEnabled else { return "Hotkey disabled" }
        
        var parts: [String] = []
        
        // Add modifier symbols
        let modifier = settings.hotkeyModifier
        if modifier.contains(.control) { parts.append("⌃") }
        if modifier.contains(.option) { parts.append("⌥") }
        if modifier.contains(.shift) { parts.append("⇧") }
        if modifier.contains(.command) { parts.append("⌘") }
        
        // Add key name
        let keyName: String
        switch settings.hotkeyKey {
        case 49: keyName = "Space"
        case 36: keyName = "Return"
        case 48: keyName = "Tab"
        case 51: keyName = "Delete"
        case 53: keyName = "Escape"
        case 123: keyName = "←"
        case 124: keyName = "→"
        case 125: keyName = "↓"
        case 126: keyName = "↑"
        default: keyName = "Key"
        }
        parts.append(keyName)
        
        return parts.joined(separator: " ") + " to record"
    }
    
    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("WhisperClip")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("Voice to Text")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 50)
                .padding(.bottom, 20)
                
                Divider()
                    .background(Color.white.opacity(0.1))
                    .padding(.horizontal, 16)
                
                // Navigation Items
                VStack(spacing: 4) {
                    ForEach(SidebarItem.allCases) { item in
                        SidebarButton(
                            item: item,
                            isSelected: selectedItem == item,
                            isHovered: hoveredItem == item
                        ) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedItem = item
                            }
                        }
                        .onHover { hovering in
                            withAnimation(.easeInOut(duration: 0.1)) {
                                hoveredItem = hovering ? item : nil
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 16)
                
                Spacer()
                
                // Footer
                VStack(spacing: 8) {
                    Divider()
                        .background(Color.white.opacity(0.1))
                        .padding(.horizontal, 16)
                    
                    HStack {
                        Image(systemName: "keyboard")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text(hotkeyString)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding(.bottom, 16)
                }
            }
            .frame(minWidth: 200, maxWidth: 220)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.95))
        } detail: {
            switch selectedItem {
            case .microphone:
                MicrophoneView()
            case .file:
                FileTranscriptionView()
            case .meetings:
                MeetingNotesView()
            case .history:
                HistoryView()
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 750, minHeight: 550)
    }
}

struct SidebarButton: View {
    let item: SidebarItem
    let isSelected: Bool
    let isHovered: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? item.color : item.color.opacity(0.15))
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: item.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(isSelected ? .white : item.color)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.rawValue)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                        .foregroundColor(isSelected ? .white : .primary)
                    
                    Text(item.description)
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                if isSelected {
                    Circle()
                        .fill(item.color)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.white.opacity(0.1) : (isHovered ? Color.white.opacity(0.05) : Color.clear))
            )
        }
        .buttonStyle(.plain)
    }
}
