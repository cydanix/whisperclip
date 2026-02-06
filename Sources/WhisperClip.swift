import SwiftUI

@main
struct WhisperClip: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openSettings) private var openSettings
    @State private var showPermissionAlert = false
    @State private var missingPermissions: [String] = []
    @StateObject private var hotkeyManager = HotkeyManager.shared
    @State private var activeSheet: ActiveSheet?

    static var shared: WhisperClip? = nil

    enum ActiveSheet: Identifiable {
        case onboarding

        var id: Int {
            switch self {
            case .onboarding: return 2
            }
        }
    }

    init() {
        Logger.log("WhisperClip initialized", log: Logger.general)
        
        // Check for Apple Silicon - app requires arm64
        #if !arch(arm64)
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Apple Silicon Required"
            alert.informativeText = "WhisperClip requires an Apple Silicon Mac (M1 or later). This app cannot run on Intel-based Macs."
            alert.alertStyle = .critical
            alert.addButton(withTitle: "Quit")
            alert.runModal()
            NSApplication.shared.terminate(nil)
        }
        #endif
        
        WhisperClip.shared = self
    }

    private func setActiveSheet(sheet: ActiveSheet?) {
        Logger.log("Setting active sheet to \(sheet?.id ?? -1)", log: Logger.general)
        if Thread.isMainThread {
            activeSheet = sheet
        } else {
            DispatchQueue.main.async {
                self.activeSheet = sheet
            }
        }
    }

    private func updateHotkeyMonitor() {
        hotkeyManager.updateSystemHotkey(
            hotkeyEnabled: SettingsStore.shared.hotkeyEnabled,
            modifier: SettingsStore.shared.hotkeyModifier,
            keyCode: SettingsStore.shared.hotkeyKey
        )
    }

    @MainActor
    func showNoEnoughDiskSpaceAlert(freeSpace: Int64) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Insufficient Disk Space"
        let availableText = freeSpace >= 0 ? "Available: \(GenericHelper.formatSize(size: freeSpace))" : "Available: unknown"
        alert.informativeText = "You need at least 20GB of free disk space to download the models. \(availableText)\n\nYou can continue anyway, but the download may fail."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Continue Anyway")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .accentColor(.orange)
                .preferredColorScheme(.dark)
                .onAppear {
                    // Ensure this process registers as a normal GUI app…
                    NSApp.setActivationPolicy(.regular)
                    // …and becomes frontmost so windows get key events
                    NSApp.activate(ignoringOtherApps: true)


                    // Show onboarding on first launch
                    if !SettingsStore.shared.hasCompletedOnboarding {
                        setActiveSheet(sheet: .onboarding)
                    } else if !SecurityChecker.shared.areAllPermissionsGranted() {
                        missingPermissions = SecurityChecker.shared.getMissingPermissions()
                        showPermissionAlert = true
                    }

                    if !showPermissionAlert && SettingsStore.shared.hasCompletedOnboarding {
                        if SettingsStore.shared.startMinimized {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                NSApp.windows.first?.miniaturize(nil)
                            }
                        }
                    }
                }
                .alert("Required Permissions", isPresented: $showPermissionAlert) {
                    Button("Open Setup Guide") {
                        showPermissionAlert = false
                        SettingsStore.shared.hasCompletedOnboarding = false
                        setActiveSheet(sheet: .onboarding)
                    }
                    Button("Later") {
                        showPermissionAlert = false
                    }
                } message: {
                    Text("The following permissions are required for the app to function properly:\n\n" + missingPermissions.joined(separator: "\n") + "\n\nWould you like to open the setup guide to configure these permissions?")
                }
                .sheet(item: $activeSheet) { sheet in
                    switch sheet {
                    case .onboarding:
                        OnboardingView()
                            .onDisappear {
                                setActiveSheet(sheet: nil)
                            }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .showSetupGuide)) { _ in
                    NSApp.activate(ignoringOtherApps: true)
                    SettingsStore.shared.hasCompletedOnboarding = false
                    setActiveSheet(sheet: .onboarding)
                }
                .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                }
        }
        Settings {
            SettingsView()
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About \(WhisperClipAppName)") {
                    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
                    let alert = NSAlert()
                    alert.messageText = "\(WhisperClipAppName) \(version)"
                    alert.informativeText = "© 2026 \(WhisperClipCompanyName)"
                    alert.alertStyle = .informational
                    alert.icon = NSApp.applicationIconImage
                    alert.addButton(withTitle: "OK")
                    alert.addButton(withTitle: "Visit Website")
                    let response = alert.runModal()
                    if response == .alertSecondButtonReturn {
                        if let url = URL(string: WhisperClipSite) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                Button("Setup Guide") {
                    SettingsStore.shared.hasCompletedOnboarding = false
                    setActiveSheet(sheet: .onboarding)
                }
            }
        }
    }
}
