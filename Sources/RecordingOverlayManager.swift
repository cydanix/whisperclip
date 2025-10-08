import SwiftUI
import AppKit

class RecordingOverlayManager {
    static let shared = RecordingOverlayManager()
    
    private var overlayWindow: NSWindow?
    
    private init() {}
    
    func show() {
        guard overlayWindow == nil else { return }
        
        let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let windowSize = NSSize(width: 200, height: 50)
        var origin = NSPoint(x: 0, y: 0)
        
        let position = SettingsStore.shared.overlayPosition
        switch position {
        case "topLeft":
            origin = NSPoint(x: 20, y: screen.height - windowSize.height - 20)
        case "topRight":
            origin = NSPoint(x: screen.width - windowSize.width - 20, y: screen.height - windowSize.height - 20)
        case "bottomLeft":
            origin = NSPoint(x: 20, y: 20)
        case "bottomRight":
            origin = NSPoint(x: screen.width - windowSize.width - 20, y: 20)
        default:
            origin = NSPoint(x: screen.width - windowSize.width - 20, y: screen.height - windowSize.height - 20)
        }
        
        let windowRect = NSRect(origin: origin, size: windowSize)
        
        overlayWindow = NSWindow(contentRect: windowRect, styleMask: .borderless, backing: .buffered, defer: false)
        overlayWindow?.level = .floating
        overlayWindow?.isOpaque = false
        overlayWindow?.backgroundColor = .clear
        overlayWindow?.ignoresMouseEvents = true
        
        let hostingView = NSHostingView(rootView: RecordingOverlayView().environmentObject(AudioRecorder.shared))
        hostingView.frame = NSRect(origin: .zero, size: windowSize)
        overlayWindow?.contentView = hostingView
        
        overlayWindow?.makeKeyAndOrderFront(nil)
    }
    
    func hide() {
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
    }
}

struct RecordingOverlayView: View {
    @EnvironmentObject var audio: AudioRecorder
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.8)
            WaveformView(audio: audio)
                .frame(height: 30)
        }
        .clipShape(Capsule())
        .frame(width: 200, height: 50)
    }
}