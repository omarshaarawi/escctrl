import Foundation

/// Wire protocol between the CLI client and the running agent, exchanged as a single JSON
/// object per connection over a Unix domain socket. Both sides live in the same binary, so
/// these types are shared directly.
enum Command: Codable {
    case status
    case setEnabled(Bool)
    case setEscapeOnTap(Bool)
    case setLogin(Bool)
    case checkUpdate
    case quit
}

struct StatusResponse: Codable {
    var enabled: Bool
    var escapeOnTap: Bool
    var login: Bool
    var accessibility: Bool
    var version: String
}

enum Response: Codable {
    case ok
    case status(StatusResponse)
    case error(String)
}
