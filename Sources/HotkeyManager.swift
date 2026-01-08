import Cocoa
import Quartz

class HotkeyManager: ObservableObject {
    private var eventTap: CFMachPort?
    var action: () -> Void = {}
    private var runLoopSource: CFRunLoopSource?
    var currentModifier: NSEvent.ModifierFlags?
    var currentKeyCode: UInt16?
    static let shared = HotkeyManager()

    private init() {
    }

    func setAction(action: @escaping () -> Void) {
        self.action = action
    }

    func setupSystemHotkey(modifier: NSEvent.ModifierFlags, keyCode: UInt16) {
        // Skip if same hotkey is already active
        if currentModifier == modifier && currentKeyCode == keyCode {
            Logger.log("Same hotkey combination already active, skipping setup", log: Logger.hotkey)
            return
        }

        removeSystemHotkey()

        Logger.log("Setting up system hotkey with modifier: \(modifier) and keyCode: \(keyCode)", log: Logger.hotkey)

        // Store current settings
        currentModifier = modifier
        currentKeyCode = keyCode

        let mask = (1 << CGEventType.keyDown.rawValue)
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: hotkeyCallback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )

        if let tap = eventTap {
            runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            Logger.log("Event tap installed", log: Logger.hotkey)
        } else {
            Logger.log("Failed to install event tap", log: Logger.hotkey, type: .error)
        }
    }

    func removeSystemHotkey() {
        Logger.log("Removing system hotkey", log: Logger.hotkey)

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let src = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
            }
            eventTap = nil
            runLoopSource = nil
            currentModifier = nil
            currentKeyCode = nil
            Logger.log("Event tap removed", log: Logger.hotkey)
        }
    }

    func updateSystemHotkey(hotkeyEnabled: Bool, modifier: NSEvent.ModifierFlags, keyCode: UInt16) {
        Logger.log("Updating hotkey monitor with modifier: \(modifier) and keyCode: \(keyCode)", log: Logger.hotkey)

        if hotkeyEnabled {
            setupSystemHotkey(
                modifier: modifier,
                keyCode: keyCode
            )
        } else {
            removeSystemHotkey()
        }
    }

    deinit {
        removeSystemHotkey()
    }
}

// Static callback function
private func hotkeyCallback(proxy: CGEventTapProxy, type: CGEventType, cgEvent: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard type == .keyDown else { return Unmanaged.passUnretained(cgEvent) }
    guard let refcon = refcon else { return Unmanaged.passUnretained(cgEvent) }

    let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
    let event = NSEvent(cgEvent: cgEvent)

    if let modifier = manager.currentModifier,
        let keyCode = manager.currentKeyCode,
        event?.modifierFlags.contains(modifier) == true,
        event?.keyCode == keyCode {
            // Run action on main thread
            DispatchQueue.main.async {
            manager.action()
        }
        return nil  // Swallow the event
    }

    return Unmanaged.passUnretained(cgEvent)
}
