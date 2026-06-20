import Foundation

enum AppPaths {
    static let bundleID = "com.omarshaarawi.escctrl"

    static let supportDir: String = NSHomeDirectory() + "/Library/Application Support/" + bundleID

    static let controlSocket: String = supportDir + "/control.sock"

    static func ensureSupportDir() {
        try? FileManager.default.createDirectory(
            atPath: supportDir,
            withIntermediateDirectories: true
        )
    }
}

enum AppInfo {
    static let version: String =
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
}

enum EscctrlError: Error, CustomStringConvertible {
    case hidutil(String)
    case tapCreationFailed
    case socket(String)

    var description: String {
        switch self {
        case .hidutil(let m): return "hidutil: \(m)"
        case .tapCreationFailed:
            return "CGEventTap creation failed (grant Accessibility permission)"
        case .socket(let m): return "socket: \(m)"
        }
    }
}
