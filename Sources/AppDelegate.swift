import Foundation
import AppKit

extension Notification.Name {
    static let showSetupGuide = Notification.Name("showSetupGuide")
    static let openSettings = Notification.Name("openSettings")
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var signalSources: [DispatchSourceSignal] = []
    private var statusItem: NSStatusItem?
    private var mainWindow: NSWindow?
    var shouldReallyQuit = false
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupSignalHandlers()
        setupStatusBarItem()
        Logger.log("Application did finish launching", log: Logger.general)
        
        // Capture the main window reference after SwiftUI creates it
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.setupMainWindowDelegate()
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if shouldReallyQuit {
            return .terminateNow
        }
        // Cmd-Q hides instead of quitting; use tray menu Quit to actually quit
        hideApp()
        return .terminateCancel
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        Logger.log("Application will terminate", log: Logger.general)
    }

    private func setupMainWindowDelegate() {
        if let window = NSApp.windows.first(where: { !($0 is NSPanel) }) {
            mainWindow = window
            window.delegate = self
        }
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hideApp()
        return false
    }

    // MARK: - App visibility

    func hideApp() {
        if mainWindow == nil {
            setupMainWindowDelegate()
        }
        mainWindow?.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
    }

    private func setupStatusBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "WhisperClip")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show \(WhisperClipAppName)", action: #selector(showApp), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Setup Guide", action: #selector(showSetupGuide), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Donate ❤️", action: #selector(openDonate), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    @objc private func showApp() {
        NSApp.setActivationPolicy(.regular)
        if mainWindow == nil {
            setupMainWindowDelegate()
        }
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() {
        shouldReallyQuit = true
        NSApplication.shared.terminate(nil)
    }

    @objc private func openDonate() {
        if let url = URL(string: WhisperClipDonateLink) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func showSetupGuide() {
        showApp()
        NotificationCenter.default.post(name: .showSetupGuide, object: nil)
    }

    @objc private func openSettings() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .openSettings, object: nil)
    }

    private func setupSignalHandlers() {
        // Handle SIGINT (Ctrl+C)
        let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        sigintSource.setEventHandler { [weak self] in
            Logger.log("Received SIGINT (Ctrl+C)", log: Logger.general)
            self?.shouldReallyQuit = true
            NSApplication.shared.terminate(nil)
        }
        sigintSource.resume()
        signalSources.append(sigintSource)
        
        // Handle SIGTERM
        let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        sigtermSource.setEventHandler { [weak self] in
            Logger.log("Received SIGTERM", log: Logger.general)
            self?.shouldReallyQuit = true
            NSApplication.shared.terminate(nil)
        }
        sigtermSource.resume()
        signalSources.append(sigtermSource)
        
        // Ignore the default signal handlers
        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)
    }
    
    deinit {
        signalSources.forEach { $0.cancel() }
    }
}
