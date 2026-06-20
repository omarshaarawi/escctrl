import Foundation
import Sparkle

/// Auto-update via Sparkle. The agent is headless, so periodic checks run in the background
/// (driven by the SUEnableAutomaticChecks / SUAutomaticallyUpdate keys in Info.plist) and
/// `escctrl update` forces an immediate check. The feed URL and EdDSA public key also live in
/// Info.plist (SUFeedURL / SUPublicEDKey), so there's no configuration in code.
final class Updater {
    private var controller: SPUStandardUpdaterController?

    /// Sparkle refuses to start without a valid feed URL and EdDSA public key, and surfaces that
    /// as a modal "the updater failed to start" alert. A headless agent must not nag, so we only
    /// start it when it's actually configured. This also covers `swift run` (no Info.plist) and
    /// un-keyed dev bundles, which would otherwise fail on launch.
    private static var isConfigured: Bool {
        let info = Bundle.main.infoDictionary
        guard let feed = info?["SUFeedURL"] as? String, !feed.isEmpty else { return false }
        guard let key = info?["SUPublicEDKey"] as? String,
            !key.isEmpty, !key.hasPrefix("REPLACE_")
        else { return false }
        return true
    }

    /// Must be called on the main thread.
    func start() {
        guard Self.isConfigured else {
            Log.info("updater disabled: Sparkle not configured (missing feed URL or public key)")
            return
        }
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        Log.info("updater started")
    }

    func checkForUpdates() {
        guard let controller else {
            Log.info("update check ignored: updater not configured")
            return
        }
        controller.updater.checkForUpdates()
    }
}
