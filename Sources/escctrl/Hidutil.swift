import Foundation

/// Remaps physical Caps Lock to F18 at the HID driver level via `hidutil`. Doing it here
/// (rather than in the event tap) means macOS never sees Caps Lock at all: no LED, no toggle.
/// The event tap then translates the F18 events into Ctrl/Escape.
enum Hidutil {
    static func remapCapsLock() throws {
        let mapping = """
        {"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":\(Keycodes.capsLockHID),\
        "HIDKeyboardModifierMappingDst":\(Keycodes.f18HID)}]}
        """
        try run(["property", "--set", mapping])
    }

    static func restoreCapsLock() throws {
        try run(["property", "--set", #"{"UserKeyMapping":[]}"#])
    }

    private static func run(_ args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = args
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = stderr.fileHandleForReading.readDataToEndOfFile()
            let msg = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown error"
            throw EscctrlError.hidutil(msg)
        }
    }
}
