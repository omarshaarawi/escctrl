import Foundation
import os

/// Diagnostic logging. Goes to the unified log (visible in Console.app / `log stream`)
/// and appends to ~/Library/Logs/escctrl.log for easy tailing while debugging.
enum Log {
    private static let logger = Logger(subsystem: AppPaths.bundleID, category: "agent")
    private static let queue = DispatchQueue(label: AppPaths.bundleID + ".log")
    private static let fileURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/escctrl.log")

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        append(message)
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        append("ERROR: " + message)
    }

    private static func append(_ message: String) {
        guard let data = (message + "\n").data(using: .utf8) else { return }
        queue.async {
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: fileURL)
            }
        }
    }
}
