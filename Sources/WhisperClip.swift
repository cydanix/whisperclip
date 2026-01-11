import SwiftUI

@main
struct WhisperClip: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
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

    func showNoEnoughDiskSpaceAlert(freeSpace: Int64) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Insufficient Disk Space"
            alert.informativeText = "You need at least 20GB of free disk space to download the models. Please free up some space and try again. Available: \(GenericHelper.formatSize(size: freeSpace))"
            alert.alertStyle = .critical
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
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
                    alert.informativeText = "© 2025 \(WhisperClipCompanyName)"
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
