import Foundation
import Darwin

/// AF_UNIX 的薄封装：地址构造、connect、bind/listen、SIGPIPE 抑制。
enum UnixSocket {
    static let addressLength = socklen_t(MemoryLayout<sockaddr_un>.size)

    static func address(path: String) -> sockaddr_un? {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        guard bytes.count < capacity else { return nil }
        withUnsafeMutablePointer(to: &addr.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { chars in
                for (index, byte) in bytes.enumerated() {
                    chars[index] = CChar(bitPattern: byte)
                }
                chars[bytes.count] = 0
            }
        }
        return addr
    }

    static func connect(path: String) -> Int32? {
        guard var addr = address(path: path) else { return nil }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        let result = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, addressLength)
            }
        }
        guard result == 0 else {
            close(fd)
            return nil
        }
        noSigPipe(fd)
        return fd
    }

    static func bindAndListen(path: String, backlog: Int32 = 16) -> Int32? {
        guard var addr = address(path: path) else { return nil }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        let result = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, addressLength)
            }
        }
        guard result == 0, listen(fd, backlog) == 0 else {
            close(fd)
            return nil
        }
        noSigPipe(fd)
        return fd
    }

    static func noSigPipe(_ fd: Int32) {
        var one: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one,
                       socklen_t(MemoryLayout<Int32>.size))
    }
}
