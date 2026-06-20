import Foundation

// Single binary, two roles, chosen by argv:
//   - a subcommand (status/on/off/…) → act as the CLI client and exit
//   - no args, "agent", or a LaunchServices "-psn_…" arg → run as the headless agent
let arguments = Array(CommandLine.arguments.dropFirst())

if let first = arguments.first, first != "agent", !first.hasPrefix("-psn") {
    exit(CLI.run(arguments))
} else {
    Agent.shared.run()
}
