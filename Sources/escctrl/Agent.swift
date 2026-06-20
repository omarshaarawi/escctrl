import AppKit
import Foundation

/// The headless daemon. Owns the keyboard engine, the hidutil remap lifecycle, and the control
/// socket. Runs as an `.accessory` app: no Dock icon, no menu bar item, no windows. Control is
/// entirely via the `escctrl` CLI talking to the socket.
final class Agent {
    static let shared = Agent()

    private let engine = KeyboardEngine()
    private var socket: ControlSocket?
    private var permissionTimer: DispatchSourceTimer?
    private var signalSources: [DispatchSourceSignal] = []
    private var engineStarted = false
    let updater = Updater()

    func run() -> Never {
        Log.info("=== escctrl agent starting (v\(AppInfo.version)) ===")
        AppPaths.ensureSupportDir()

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        engine.enabled = Settings.enabled
        engine.escapeOnTap = Settings.escapeOnTap

        installSignalHandlers()
        startControlSocket()

        Permissions.requestAccessibility()
        startEngineWithRetry()

        updater.start()

        app.run()
        // app.run() does not return; this satisfies -> Never.
        fatalError("NSApplication.run returned")
    }

    // MARK: - Engine startup (retries until Accessibility is granted)

    private func startEngineWithRetry() {
        if tryStartEngine() { return }

        Log.info("waiting for accessibility permission...")
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 2, repeating: 2)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            if self.tryStartEngine() {
                Log.info("engine started after permission granted")
                self.permissionTimer?.cancel()
                self.permissionTimer = nil
            }
        }
        timer.resume()
        permissionTimer = timer
    }

    private func tryStartEngine() -> Bool {
        if engineStarted { return true }
        do {
            try engine.start()
            engineStarted = true
            Log.info("engine started; applying hidutil remap")
            do {
                try Hidutil.remapCapsLock()
                Log.info("hidutil remap OK")
            } catch {
                Log.error("hidutil remap failed: \(error)")
            }
            return true
        } catch {
            return false
        }
    }

    // MARK: - Control socket

    private func startControlSocket() {
        let sock = ControlSocket(path: AppPaths.controlSocket) { [weak self] command in
            guard let self else { return .error("agent shutting down") }
            return DispatchQueue.main.sync { self.handle(command) }
        }
        do {
            try sock.start()
            socket = sock
        } catch {
            Log.error("control socket failed to start: \(error)")
        }
    }

    /// Runs on the main thread (hopped from the socket's background queue).
    private func handle(_ command: Command) -> Response {
        switch command {
        case .status:
            return .status(StatusResponse(
                enabled: engine.enabled,
                escapeOnTap: engine.escapeOnTap,
                login: LoginItem.isEnabled,
                accessibility: Permissions.isTrusted,
                version: AppInfo.version
            ))

        case .setEnabled(let value):
            engine.enabled = value
            Settings.enabled = value
            return .ok

        case .setEscapeOnTap(let value):
            engine.escapeOnTap = value
            Settings.escapeOnTap = value
            return .ok

        case .setLogin(let value):
            do {
                try LoginItem.setEnabled(value)
                return .ok
            } catch {
                return .error("login item: \(error.localizedDescription)")
            }

        case .checkUpdate:
            updater.checkForUpdates()
            return .ok

        case .quit:
            DispatchQueue.main.async { [weak self] in self?.shutdown() }
            return .ok
        }
    }

    // MARK: - Shutdown / cleanup

    private func installSignalHandlers() {
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)  // disable default handler so the dispatch source gets it
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler { [weak self] in self?.shutdown() }
            src.resume()
            signalSources.append(src)
        }
    }

    private func shutdown() -> Never {
        Log.info("shutting down; restoring Caps Lock")
        do {
            try Hidutil.restoreCapsLock()
        } catch {
            Log.error("restore failed: \(error)")
        }
        engine.stop()
        socket?.stop()
        exit(0)
    }
}
