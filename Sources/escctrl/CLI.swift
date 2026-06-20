import Foundation

/// Command-line front end. Translates `escctrl <subcommand>` into a `Command`, sends it to the
/// running agent, and prints a human-readable result. Returns a process exit code.
enum CLI {
    static func run(_ args: [String]) -> Int32 {
        guard let first = args.first else { return usage("no command given") }
        switch first {
        case "status":
            return status()
        case "on":
            return ack(.setEnabled(true), "remapping enabled")
        case "off":
            return ack(.setEnabled(false), "remapping disabled")
        case "escape":
            return onOff(args, label: "escape-on-tap") { .setEscapeOnTap($0) }
        case "login":
            return onOff(args, label: "launch-at-login") { .setLogin($0) }
        case "update":
            return ack(.checkUpdate, "checking for updates")
        case "quit":
            return ack(.quit, "agent quitting")
        case "help", "-h", "--help":
            printUsage()
            return 0
        default:
            return usage("unknown command: \(first)")
        }
    }

    // MARK: - Subcommands

    private static func status() -> Int32 {
        switch Client.send(.status) {
        case .status(let s):
            print("""
            escctrl v\(s.version)
              remapping:        \(s.enabled ? "enabled" : "disabled")
              escape-on-tap:    \(s.escapeOnTap ? "on" : "off")
              launch-at-login:  \(s.login ? "on" : "off")
              accessibility:    \(s.accessibility ? "granted" : "NOT granted")
            """)
            return 0
        case .error(let message):
            return fail(message)
        case .ok:
            return fail("unexpected response")
        }
    }

    private static func onOff(_ args: [String], label: String, _ make: (Bool) -> Command) -> Int32 {
        guard args.count >= 2, let value = parseBool(args[1]) else {
            return usage("usage: escctrl \(args[0]) on|off")
        }
        return ack(make(value), "\(label) \(value ? "on" : "off")")
    }

    private static func ack(_ command: Command, _ success: String) -> Int32 {
        switch Client.send(command) {
        case .ok, .status:
            print(success)
            return 0
        case .error(let message):
            return fail(message)
        }
    }

    // MARK: - Helpers

    private static func parseBool(_ s: String) -> Bool? {
        switch s.lowercased() {
        case "on", "true", "yes", "1", "enable", "enabled": return true
        case "off", "false", "no", "0", "disable", "disabled": return false
        default: return nil
        }
    }

    @discardableResult
    private static func fail(_ message: String) -> Int32 {
        FileHandle.standardError.write(Data(("error: " + message + "\n").utf8))
        return 1
    }

    private static func usage(_ message: String) -> Int32 {
        fail(message)
        printUsage(to: .standardError)
        return 2
    }

    static func printUsage(to handle: FileHandle = .standardOutput) {
        let text = """
        escctrl — Caps Lock → Ctrl (hold) / Escape (tap)

        Usage:
          escctrl                run the agent (normally launched at login)
          escctrl status         show current state
          escctrl on | off       enable / disable remapping
          escctrl escape on|off  Escape-on-tap (off = Ctrl-only)
          escctrl login on|off   launch at login
          escctrl update         check for updates now
          escctrl quit           stop the agent
        """
        handle.write(Data((text + "\n").utf8))
    }
}
