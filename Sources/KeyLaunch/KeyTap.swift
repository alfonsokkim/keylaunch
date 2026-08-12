import Cocoa

private let systemDefinedType = CGEventType(rawValue: 14)!  // NSEventTypeSystemDefined

final class KeyTap {
    static let shared = KeyTap()

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    var isRunning: Bool { tap != nil }

    /// Returns false if Accessibility permission is missing (or was revoked).
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }

        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << systemDefinedType.rawValue)

        // .cghidEventTap is the earliest point in the chain. It matters here:
        // the function-row keys are claimed by the window server, so a tap
        // placed any later never sees them and cannot swallow them.
        guard let port = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, _ in KeyTap.shared.handle(type: type, event: event) },
            userInfo: nil
        ) else { return false }

        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tap = port
        source = src
        return true
    }

    func stop() {
        if let port = tap { CGEvent.tapEnable(tap: port, enable: false) }
        if let src = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        tap = nil
        source = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // The system disables a tap that takes too long or after certain input;
        // re-arming is the documented recovery.
        if type.rawValue == 0xFFFF_FFFE || type.rawValue == 0xFFFF_FFFF {
            if let port = tap { CGEvent.tapEnable(tap: port, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        guard let parsed = decode(type: type, event: event) else {
            return Unmanaged.passUnretained(event)
        }

        let store = Store.shared

        if let learningID = store.learningID {
            // Escape cancels instead of being captured, so a mis-click is recoverable.
            if parsed.trigger == .key(53) {
                if parsed.isDown { store.learningID = nil }
                return nil
            }
            if parsed.isDown {
                store.setTrigger(parsed.trigger, for: learningID)
                store.learningID = nil
            }
            return nil  // swallow both halves of the press
        }

        guard let mapping = store.mapping(for: parsed.trigger), let url = mapping.appURL else {
            return Unmanaged.passUnretained(event)
        }

        if parsed.isDown && !parsed.isRepeat {
            activate(url, name: mapping.appName ?? url.lastPathComponent)
        }
        return nil  // swallow, so Mission Control / Spotlight does not also fire
    }

    private struct Parsed {
        let trigger: Trigger
        let isDown: Bool
        let isRepeat: Bool
    }

    private func decode(type: CGEventType, event: CGEvent) -> Parsed? {
        if type == .keyDown {
            let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
            let repeated = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            // Ignore anything with modifiers held: those belong to real shortcuts.
            let flags = event.flags
            let interesting: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
            if !flags.intersection(interesting).isEmpty { return nil }
            return Parsed(trigger: .key(code), isDown: true, isRepeat: repeated)
        }

        guard type == systemDefinedType, let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8
        else { return nil }

        let data1 = ns.data1
        let code = (data1 & 0xFFFF_0000) >> 16
        let state = (data1 & 0x0000_FF00) >> 8
        let repeated = (data1 & 0x1) == 1
        return Parsed(trigger: .system(code), isDown: state == 0x0A, isRepeat: repeated)
    }

    private func activate(_ url: URL, name: String) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        // openApplication brings the app forward if it is already running and
        // launches it otherwise, which is exactly the switch-or-open behaviour.
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            DispatchQueue.main.async {
                Store.shared.lastFired = error == nil ? name : "Could not open \(name)"
            }
        }
    }
}
