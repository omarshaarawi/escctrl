import ApplicationServices

/// Accessibility permission gating. The real source of truth for "can we intercept keys" is
/// whether `CGEvent.tapCreate` succeeds (see `KeyboardEngine`); this just nudges the user with
/// the system prompt and exposes the trust state for `status`.
enum Permissions {
    @discardableResult
    static func requestAccessibility() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }
}
