import Foundation

/// Low-level helpers shared by the socket server (`ControlSocket`) and the CLI client (`Client`).
/// One request and one response per connection; the writer half-closes (`shutdown(SHUT_WR)`)
/// so the reader sees EOF and knows the message is complete. No length framing needed.
enum UnixSocket {
    /// Builds a `sockaddr_un` for `path` and hands `body` a `sockaddr` pointer for bind/connect.
    static func withAddress<R>(
        _ path: String,
        _ body: (UnsafePointer<sockaddr>, socklen_t) -> R
    ) throws -> R {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        guard pathBytes.count < capacity else {
            throw EscctrlError.socket("path too long (\(pathBytes.count) >= \(capacity)): \(path)")
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: pathBytes)
            raw[pathBytes.count] = 0
        }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        return withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, len) }
        }
    }

    static func readAll(_ fd: Int32) -> Data {
        var data = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = buf.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if n > 0 {
                data.append(contentsOf: buf[0..<n])
            } else {
                break  // 0 == EOF, <0 == error
            }
        }
        return data
    }

    static func writeAll(_ fd: Int32, _ data: Data) {
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard var base = raw.baseAddress else { return }
            var remaining = raw.count
            while remaining > 0 {
                let n = write(fd, base, remaining)
                if n <= 0 { break }
                base = base.advanced(by: n)
                remaining -= n
            }
        }
    }
}
