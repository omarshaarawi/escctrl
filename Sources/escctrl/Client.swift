import Foundation

/// CLI side of the control protocol: connect, send one command, read one response.
enum Client {
    /// Returns `.error("agent not running")` if nothing is listening on the socket.
    static func send(_ command: Command, socketPath: String = AppPaths.controlSocket) -> Response {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return .error("socket(): \(String(cString: strerror(errno)))") }
        defer { close(fd) }

        let connected: Int32
        do {
            connected = try UnixSocket.withAddress(socketPath) { connect(fd, $0, $1) }
        } catch {
            return .error("\(error)")
        }
        guard connected == 0 else { return .error("agent not running") }

        guard let data = try? JSONEncoder().encode(command) else {
            return .error("failed to encode command")
        }
        UnixSocket.writeAll(fd, data)
        shutdown(fd, Int32(SHUT_WR))  // signal end-of-request

        let responseData = UnixSocket.readAll(fd)
        guard let response = try? JSONDecoder().decode(Response.self, from: responseData) else {
            return .error("malformed response")
        }
        return response
    }
}
