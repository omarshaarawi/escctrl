import Foundation

/// Listens on a Unix domain socket for CLI commands. Each accepted connection carries exactly
/// one `Command`; the handler returns a `Response`. Accept runs on a background queue, so the
/// handler must be safe to call off the main thread (the agent hops to main internally).
final class ControlSocket {
    private let path: String
    private let handler: (Command) -> Response
    private var listenFD: Int32 = -1
    private var source: DispatchSourceRead?

    init(path: String, handler: @escaping (Command) -> Response) {
        self.path = path
        self.handler = handler
    }

    func start() throws {
        unlink(path)  // clear any stale socket from a previous run

        listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenFD >= 0 else {
            throw EscctrlError.socket("socket(): \(errnoString())")
        }

        let bound = try UnixSocket.withAddress(path) { bind(listenFD, $0, $1) }
        guard bound == 0 else {
            close(listenFD)
            throw EscctrlError.socket("bind(): \(errnoString())")
        }
        chmod(path, 0o600)

        guard listen(listenFD, 4) == 0 else {
            close(listenFD)
            throw EscctrlError.socket("listen(): \(errnoString())")
        }

        let src = DispatchSource.makeReadSource(fileDescriptor: listenFD, queue: .global())
        src.setEventHandler { [weak self] in self?.acceptOne() }
        src.setCancelHandler { [listenFD] in close(listenFD) }
        src.resume()
        source = src
        Log.info("control socket listening at \(path)")
    }

    func stop() {
        source?.cancel()
        source = nil
        unlink(path)
    }

    private func acceptOne() {
        let clientFD = accept(listenFD, nil, nil)
        guard clientFD >= 0 else { return }
        defer { close(clientFD) }

        let requestData = UnixSocket.readAll(clientFD)
        let response: Response
        if let command = try? JSONDecoder().decode(Command.self, from: requestData) {
            response = handler(command)
        } else {
            response = .error("malformed request")
        }
        if let data = try? JSONEncoder().encode(response) {
            UnixSocket.writeAll(clientFD, data)
        }
    }

    private func errnoString() -> String {
        String(cString: strerror(errno))
    }
}
