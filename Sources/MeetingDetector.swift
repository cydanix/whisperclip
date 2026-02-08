import Foundation
import AppKit
import Combine

/// Detects when meeting applications are active
@MainActor
class MeetingDetector: ObservableObject {
    static let shared = MeetingDetector()
    
    @Published private(set) var isDetectionEnabled: Bool = false
    @Published private(set) var detectedSource: MeetingSource?
    @Published private(set) var isMeetingActive: Bool = false
    @Published private(set) var activeAppName: String?
    
    private var detectionTimer: Timer?
    private let detectionInterval: TimeInterval = 2.0
    private var lastDetectedApp: String?
    private var meetingStartTime: Date?
    
    // Known meeting app bundle identifiers
    private let meetingAppBundleIds: [String: MeetingSource] = [
        "us.zoom.xos": .zoom,
        "zoom.us": .zoom,
        "com.microsoft.teams": .teams,
        "com.microsoft.teams2": .teams,
        "com.cisco.webex": .webex,
        "Cisco-Systems.Spark": .webex,
        "com.tinyspeck.slackmacgap": .slack,
        "com.hnc.Discord": .discord,
        "com.apple.FaceTime": .facetime,
    ]
    
    // Window title patterns that indicate an active meeting
    private let meetingWindowPatterns: [String: MeetingSource] = [
        "Zoom Meeting": .zoom,
        "Zoom Webinar": .zoom,
        "meeting with": .teams,
        "Microsoft Teams": .teams,
        "Google Meet": .meet,
        "meet.google.com": .meet,
        "Webex Meeting": .webex,
        "Huddle": .slack,
        "Voice Connected": .discord,
        "FaceTime": .facetime,
    ]
    
    private init() {}
    
    // MARK: - Detection Control
    
    func startDetection() {
        guard !isDetectionEnabled else { return }
        
        isDetectionEnabled = true
        detectionTimer = Timer.scheduledTimer(withTimeInterval: detectionInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForMeetingApps()
            }
        }
        
        // Run immediately
        checkForMeetingApps()
        Logger.log("Meeting detection started", log: Logger.general)
    }
    
    func stopDetection() {
        isDetectionEnabled = false
        detectionTimer?.invalidate()
        detectionTimer = nil
        detectedSource = nil
        isMeetingActive = false
        activeAppName = nil
        Logger.log("Meeting detection stopped", log: Logger.general)
    }
    
    // MARK: - Detection Logic
    
    private func checkForMeetingApps() {
        // Check running applications
        let runningApps = NSWorkspace.shared.runningApplications
        
        for app in runningApps {
            guard let bundleId = app.bundleIdentifier else { continue }
            
            // Check if it's a known meeting app with a meeting window open
            if let source = meetingAppBundleIds[bundleId] {
                if isAppInMeeting(app: app, source: source) {
                    handleMeetingDetected(source: source, appName: app.localizedName ?? source.rawValue)
                    return
                }
            }
        }
        
        // Check for web-based meetings (Meet in browser)
        if let browserMeeting = checkBrowserForMeetings() {
            handleMeetingDetected(source: browserMeeting.source, appName: browserMeeting.name)
            return
        }
        
        // No meeting detected
        if isMeetingActive {
            handleMeetingEnded()
        }
    }
    
    private func isAppInMeeting(app: NSRunningApplication, source: MeetingSource) -> Bool {
        // For some apps, we can check window titles to confirm a meeting is active
        // This requires accessibility permissions
        
        guard let windows = getWindowsForApp(app) else { return false }
        
        let keywords = source.windowTitleKeywords
        for window in windows {
            for keyword in keywords {
                if window.localizedCaseInsensitiveContains(keyword) {
                    return true
                }
            }
        }
        
        return false
    }
    
    private func getWindowsForApp(_ app: NSRunningApplication) -> [String]? {
        // Get window list using CGWindowListCopyWindowInfo (include all windows, not just on-screen)
        guard let windowList = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        
        var titles: [String] = []
        let pid = app.processIdentifier
        
        for window in windowList {
            guard let windowPid = window[kCGWindowOwnerPID as String] as? Int32,
                  windowPid == pid,
                  let title = window[kCGWindowName as String] as? String,
                  !title.isEmpty else {
                continue
            }
            titles.append(title)
        }
        
        return titles.isEmpty ? nil : titles
    }
    
    private func checkBrowserForMeetings() -> (source: MeetingSource, name: String)? {
        // Check popular browsers for meeting URLs in window titles
        let browserBundleIds = [
            "com.google.Chrome",
            "com.apple.Safari",
            "com.microsoft.edgemac",
            "org.mozilla.firefox",
            "com.brave.Browser"
        ]
        
        let runningApps = NSWorkspace.shared.runningApplications
        
        for app in runningApps {
            guard let bundleId = app.bundleIdentifier,
                  browserBundleIds.contains(bundleId),
                  let windows = getWindowsForApp(app) else {
                continue
            }
            
            for window in windows {
                // Check for Google Meet
                if window.localizedCaseInsensitiveContains("meet.google.com") ||
                   window.localizedCaseInsensitiveContains("Google Meet") {
                    return (.meet, "Google Meet")
                }
                
                // Check for Zoom in browser
                if window.localizedCaseInsensitiveContains("zoom.us") &&
                   (window.localizedCaseInsensitiveContains("meeting") ||
                    window.localizedCaseInsensitiveContains("webinar")) {
                    return (.zoom, "Zoom (Browser)")
                }
                
                // Check for Teams in browser
                if window.localizedCaseInsensitiveContains("teams.microsoft.com") ||
                   window.localizedCaseInsensitiveContains("teams.live.com") {
                    return (.teams, "Teams (Browser)")
                }
            }
        }
        
        return nil
    }
    
    private func handleMeetingDetected(source: MeetingSource, appName: String) {
        let wasActive = isMeetingActive
        let previousSource = detectedSource
        
        detectedSource = source
        isMeetingActive = true
        activeAppName = appName
        
        if !wasActive {
            // New meeting started
            meetingStartTime = Date()
            NotificationCenter.default.post(name: .meetingAppDetected, object: source)
            Logger.log("Meeting detected: \(source.rawValue) - \(appName)", log: Logger.general)
        } else if previousSource != source {
            // Switched meeting apps
            Logger.log("Meeting app changed: \(source.rawValue) - \(appName)", log: Logger.general)
        }
    }
    
    private func handleMeetingEnded() {
        guard isMeetingActive else { return }
        
        let previousSource = detectedSource
        isMeetingActive = false
        detectedSource = nil
        activeAppName = nil
        
        if let source = previousSource {
            NotificationCenter.default.post(name: .meetingAppClosed, object: source)
            Logger.log("Meeting ended: \(source.rawValue)", log: Logger.general)
        }
        
        meetingStartTime = nil
    }
    
    // MARK: - Manual Control
    
    func manuallySetMeetingActive(source: MeetingSource = .manual) {
        handleMeetingDetected(source: source, appName: source.rawValue)
    }
    
    func manuallyEndMeeting() {
        handleMeetingEnded()
    }
    
    // MARK: - Status
    
    var meetingDuration: TimeInterval? {
        guard let startTime = meetingStartTime else { return nil }
        return Date().timeIntervalSince(startTime)
    }
    
    var formattedMeetingDuration: String {
        guard let duration = meetingDuration else { return "--:--" }
        
        let totalSeconds = Int(duration)
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
