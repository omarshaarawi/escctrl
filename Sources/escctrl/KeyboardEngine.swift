import CoreGraphics
import Foundation

/// Intercepts the (remapped) F18 events at the HID tap and translates them:
///   - hold F18 + another key  → that key gets Ctrl applied
///   - tap  F18 (< threshold)  → synthesize Escape
/// Caps Lock's own AlphaShift flag changes are dropped so the LED/toggle never fires.
final class KeyboardEngine {
    private let lock = NSLock()
    private var _enabled = true
    private var _escapeOnTap = true

    private let tracker: CapsLockTracker
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var firstEventLogged = false

    init(tapThresholdMs: UInt64 = Keycodes.defaultTapThresholdMs) {
        self.tracker = CapsLockTracker(tapThresholdMs: tapThresholdMs)
    }

    var enabled: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _enabled }
        set { lock.lock(); _enabled = newValue; lock.unlock() }
    }

    var escapeOnTap: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _escapeOnTap }
        set { lock.lock(); _escapeOnTap = newValue; lock.unlock() }
    }

    /// Creates the event tap and wires it into the main run loop. Throws if Accessibility
    /// permission is missing (the OS refuses to create the tap). Idempotent.
    func start() throws {
        if eventTap != nil { return }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw EscctrlError.tapCreationFailed
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
        Log.info("event tap created and enabled")
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    // MARK: - Event handling (runs on the main run loop)

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS disables the tap if a callback runs too long or on some input transitions.
        // Re-enable it instead of silently going dead (the Rust version logged but never recovered).
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            Log.error("event tap disabled (\(type.rawValue)); re-enabled")
            return Unmanaged.passUnretained(event)
        }

        if !firstEventLogged {
            firstEventLogged = true
            Log.info("first event in callback: type=\(type.rawValue)")
        }

        if !enabled {
            return Unmanaged.passUnretained(event)
        }

        let keycode = CGKeyCode(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))

        switch type {
        case .keyDown:
            if keycode == Keycodes.f18 {
                if !tracker.isHeld { tracker.press() }
                return nil  // swallow F18 itself
            }
            if tracker.isHeld {
                tracker.interrupt()
                event.flags.insert(.maskControl)
            }
            return Unmanaged.passUnretained(event)

        case .keyUp:
            if keycode == Keycodes.f18 {
                let wasTap = tracker.release()
                if wasTap && escapeOnTap {
                    postEscape()
                }
                return nil  // swallow F18 itself
            }
            if tracker.isHeld {
                event.flags.insert(.maskControl)
            }
            return Unmanaged.passUnretained(event)

        case .flagsChanged:
            // Drop the Caps Lock toggle flag so the LED/state never flips.
            if event.flags.contains(.maskAlphaShift) {
                return nil
            }
            return Unmanaged.passUnretained(event)

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func postEscape() {
        guard let source = CGEventSource(stateID: .privateState) else { return }
        CGEvent(keyboardEventSource: source, virtualKey: Keycodes.escape, keyDown: true)?
            .post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: source, virtualKey: Keycodes.escape, keyDown: false)?
            .post(tap: .cghidEventTap)
    }
}

/// C-compatible trampoline. Recovers the engine from `userInfo` (passed unretained in `start`).
private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let engine = Unmanaged<KeyboardEngine>.fromOpaque(userInfo).takeUnretainedValue()
    return engine.handle(type: type, event: event)
}
