import Foundation

/// Tracks the press/hold lifecycle of the (remapped) Caps Lock key so the engine can
/// decide whether a release was a quick *tap* (→ Escape) or a *hold* (→ Ctrl modifier).
///
///   idle ──press──▶ pressed ──(another key)──▶ heldAsCtrl
///     ▲                │                              │
///     └──────release───┴──────────release────────────┘
///
/// Only ever touched from the event-tap callback (single-threaded on the main run loop),
/// so it needs no locking of its own.
final class CapsLockTracker {
    private enum State {
        case idle
        case pressed(at: UInt64)  // DispatchTime uptime nanoseconds
        case heldAsCtrl
    }

    private var state: State = .idle
    private var tapThresholdMs: UInt64
    private var interrupted = false
    private let now: () -> UInt64

    /// `now` returns a monotonic timestamp in nanoseconds; injectable so the timing logic can be
    /// unit-tested deterministically.
    init(tapThresholdMs: UInt64, now: @escaping () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }) {
        self.tapThresholdMs = tapThresholdMs
        self.now = now
    }

    func press() {
        state = .pressed(at: now())
        interrupted = false
    }

    /// Another key was pressed while Caps was down: this is now unambiguously a hold.
    func interrupt() {
        if case .pressed = state {
            state = .heldAsCtrl
        }
        interrupted = true
    }

    /// Returns true if the release should fire an Escape (i.e. it was a clean tap).
    func release() -> Bool {
        let wasTap: Bool
        switch state {
        case .pressed(let at):
            let elapsedMs = (now() &- at) / 1_000_000
            wasTap = elapsedMs < tapThresholdMs && !interrupted
        default:
            wasTap = false
        }
        state = .idle
        interrupted = false
        return wasTap
    }

    var isHeld: Bool {
        switch state {
        case .pressed, .heldAsCtrl: return true
        case .idle: return false
        }
    }

    func setThreshold(_ ms: UInt64) {
        tapThresholdMs = ms
    }
}
