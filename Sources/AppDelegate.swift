import Foundation
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var signalSources: [DispatchSourceSignal] = []
    private var statusItem: NSStatusItem?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupSignalHandlers()
        setupStatusBarItem()
        Logger.log("Application did finish launching", log: Logger.general)
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        Logger.log("Application will terminate", log: Logger.general)
    }

    private func setupStatusBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "WhisperClip")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show \(WhisperClipAppName)", action: #selector(showApp), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Donate ❤️", action: #selector(openDonate), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    @objc private func showApp() {
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openDonate() {
        if let url = URL(string: WhisperClipDonateLink) {
            NSWorkspace.shared.open(url)
        }
    }

    private func setupSignalHandlers() {
        // Handle SIGINT (Ctrl+C)
        let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        sigintSource.setEventHandler {
            Logger.log("Received SIGINT (Ctrl+C)", log: Logger.general)
            NSApplication.shared.terminate(nil)
        }
        sigintSource.resume()
        signalSources.append(sigintSource)
        
        // Handle SIGTERM
        let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        sigtermSource.setEventHandler {
            Logger.log("Received SIGTERM", log: Logger.general)
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
