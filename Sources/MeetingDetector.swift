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
    
    /// Throttle diagnostic logging to avoid spamming every 2 seconds
    private var lastDiagnosticLog: Date = .distantPast
    
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
        let enabledApps = Set(SettingsStore.shared.meetingDetectedApps)
        let runningApps = NSWorkspace.shared.runningApplications
        let shouldLogDiag = Date().timeIntervalSince(lastDiagnosticLog) > 30
        
        for app in runningApps {
            guard let bundleId = app.bundleIdentifier else { continue }
            
            if let source = meetingAppBundleIds[bundleId] {
                guard enabledApps.contains(source.rawValue) else { continue }
                
                let result = isAppInMeeting(app: app, source: source)
                
                if shouldLogDiag {
                    lastDiagnosticLog = Date()
                    Logger.log("Detection check: \(source.rawValue) running, windows=\(result.windowTitles ?? []), matched=\(result.isInMeeting), active=\(app.isActive)", log: Logger.general)
                }
                
                if result.isInMeeting {
                    handleMeetingDetected(source: source, appName: app.localizedName ?? source.rawValue)
                    return
                }
            }
        }
        
        // Check for web-based meetings (Meet in browser)
        for browserMeeting in checkBrowserForMeetings() {
            guard enabledApps.contains(browserMeeting.source.rawValue) else { continue }
            handleMeetingDetected(source: browserMeeting.source, appName: browserMeeting.name)
            return
        }
        
        // No meeting detected
        if isMeetingActive {
            handleMeetingEnded()
        }
    }
    
    private func isAppInMeeting(app: NSRunningApplication, source: MeetingSource) -> (isInMeeting: Bool, windowTitles: [String]?) {
        let windowInfo = getWindowsForApp(app)
        let titles = windowInfo.titles
        let totalWindowCount = windowInfo.totalCount
        
        // Strategy 1: Match window titles against meeting keywords
        if let titles = titles {
            let keywords = source.windowTitleKeywords
            for title in titles {
                for keyword in keywords {
                    if title.localizedCaseInsensitiveContains(keyword) {
                        return (true, titles)
                    }
                }
            }
            
            // Strategy 2: For apps that have known non-meeting window titles,
            // if there are windows beyond the non-meeting ones, likely in a meeting.
            // e.g. Zoom shows "Zoom Workplace" when idle; extra windows = meeting active
            let nonMeetingKeywords = source.nonMeetingWindowKeywords
            if !nonMeetingKeywords.isEmpty {
                let meetingWindows = titles.filter { title in
                    !nonMeetingKeywords.contains(where: { title.localizedCaseInsensitiveContains($0) })
                }
                if !meetingWindows.isEmpty {
                    return (true, titles)
                }
            }
        }
        
        // Strategy 3: Fallback when we cannot read window titles
        // (no Screen Recording permission — CGWindowListCopyWindowInfo returns empty names).
        // If the app is the frontmost (active) application AND has multiple windows,
        // treat it as likely being in a meeting.
        if titles == nil && app.isActive && totalWindowCount >= 2 {
            return (true, nil)
        }
        
        return (false, titles)
    }
    
    /// Returns window titles (if accessible) and total window count for the app
    private func getWindowsForApp(_ app: NSRunningApplication) -> (titles: [String]?, totalCount: Int) {
        guard let windowList = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
            return (nil, 0)
        }
        
        var titles: [String] = []
        var totalCount = 0
        let pid = app.processIdentifier
        
        for window in windowList {
            guard let windowPid = window[kCGWindowOwnerPID as String] as? Int32,
                  windowPid == pid else {
                continue
            }
            
            // Count all windows regardless of whether we can read their title
            let layer = window[kCGWindowLayer as String] as? Int ?? 0
            if layer == 0 {  // Normal window layer only
                totalCount += 1
            }
            
            if let title = window[kCGWindowName as String] as? String, !title.isEmpty {
                titles.append(title)
            }
        }
        
        return (titles.isEmpty ? nil : titles, totalCount)
    }
    
    private func checkBrowserForMeetings() -> [(source: MeetingSource, name: String)] {
        // Check popular browsers for meeting URLs in window titles
        let browserBundleIds = [
            "com.google.Chrome",
            "com.apple.Safari",
            "com.microsoft.edgemac",
            "org.mozilla.firefox",
            "com.brave.Browser"
        ]
        
        var results: [(source: MeetingSource, name: String)] = []
        var foundSources: Set<MeetingSource> = []
        let runningApps = NSWorkspace.shared.runningApplications
        
        for app in runningApps {
            guard let bundleId = app.bundleIdentifier,
                  browserBundleIds.contains(bundleId),
                  let windows = getWindowsForApp(app).titles else {
                continue
            }
            
            for window in windows {
                // Check for Google Meet
                if !foundSources.contains(.meet) &&
                   (window.localizedCaseInsensitiveContains("meet.google.com") ||
                    window.localizedCaseInsensitiveContains("Google Meet")) {
                    results.append((.meet, "Google Meet"))
                    foundSources.insert(.meet)
                }
                
                // Check for Zoom in browser
                if !foundSources.contains(.zoom) &&
                   window.localizedCaseInsensitiveContains("zoom.us") &&
                   (window.localizedCaseInsensitiveContains("meeting") ||
                    window.localizedCaseInsensitiveContains("webinar")) {
                    results.append((.zoom, "Zoom (Browser)"))
                    foundSources.insert(.zoom)
                }
                
                // Check for Teams in browser
                if !foundSources.contains(.teams) &&
                   (window.localizedCaseInsensitiveContains("teams.microsoft.com") ||
                    window.localizedCaseInsensitiveContains("teams.live.com")) {
                    results.append((.teams, "Teams (Browser)"))
                    foundSources.insert(.teams)
                }
            }
        }
        
        return results
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
