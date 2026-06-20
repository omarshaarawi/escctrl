import Foundation

/// Persisted agent settings, backed by `UserDefaults` (under the app's bundle id). Only the
/// agent reads/writes these; the CLI changes behavior by talking to the running agent, which
/// then persists. Login-at-launch state is owned by `SMAppService`, not stored here.
enum Settings {
    private static let defaults = UserDefaults.standard
    private enum Key {
        static let enabled = "enabled"
        static let escapeOnTap = "escape_on_tap"
    }

    static var enabled: Bool {
        get { defaults.object(forKey: Key.enabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.enabled) }
    }

    static var escapeOnTap: Bool {
        get { defaults.object(forKey: Key.escapeOnTap) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.escapeOnTap) }
    }
}
