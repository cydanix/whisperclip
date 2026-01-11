import SwiftUI
import AppKit

class RecordingOverlayManager {
    static let shared = RecordingOverlayManager()

    private var overlayWindow: NSWindow?

    private init() {
        // Subscribe to recording finish/error notifications to ensure overlay is hidden
        // even if ContentView is destroyed (e.g., main window closed during recording)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRecordingFinished),
            name: .didFinishRecording,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRecordingError),
            name: .recordingError,
            object: nil
        )
    }
    
    @objc private func handleRecordingFinished(_ notification: Notification) {
        hide()
    }
    
    @objc private func handleRecordingError(_ notification: Notification) {
        hide()
    }

    func show() {
        guard overlayWindow == nil else { return }

        // Use visibleFrame to avoid menu bar and Dock
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let windowSize = NSSize(width: 200, height: 50)
        var origin = NSPoint(x: 0, y: 0)
        let padding: CGFloat = 20

        let position = SettingsStore.shared.overlayPosition
        switch position {
        case "topLeft":
            origin = NSPoint(x: visibleFrame.minX + padding, y: visibleFrame.maxY - windowSize.height - padding)
        case "topRight":
            origin = NSPoint(x: visibleFrame.maxX - windowSize.width - padding, y: visibleFrame.maxY - windowSize.height - padding)
        case "bottomLeft":
            origin = NSPoint(x: visibleFrame.minX + padding, y: visibleFrame.minY + padding)
        case "bottomRight":
            origin = NSPoint(x: visibleFrame.maxX - windowSize.width - padding, y: visibleFrame.minY + padding)
        default:
            origin = NSPoint(x: visibleFrame.maxX - windowSize.width - padding, y: visibleFrame.maxY - windowSize.height - padding)
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