import AppKit
import Darwin
import Foundation
import PinShellCore

enum ControlClientError: Error, LocalizedError {
    case appUnavailable(String)
    case connectionFailed(String)
    case timeout
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .appUnavailable(let message): return message
        case .connectionFailed(let message): return message
        case .timeout: return "timed out waiting for PinShell"
        case .transport(let message): return message
        }
    }

    var exitCode: Int32 {
        switch self {
        case .appUnavailable, .connectionFailed, .timeout, .transport:
            return 2
        }
    }
}

/// CLI 侧同步客户端：连接 socket、必要时拉起 App、收发一行 JSON。
enum ControlClient {
    // MARK: - 请求

    static func request(_ request: ControlRequest,
                        timeout: TimeInterval = 10,
                        launchIfNeeded: Bool = true) throws -> ControlResponse {
        let fd = try openConnection(launchIfNeeded: launchIfNeeded)
        defer { closeConnection(fd) }

        try writeAll(fd: fd, data: ControlWire.encodeLine(request))
        guard let line = try readLine(fd: fd, timeout: timeout) else {
            throw ControlClientError.transport("connection closed before response")
        }
        do {
            return try ControlWire.decodeLine(line, as: ControlResponse.self)
        } catch {
            throw ControlClientError.transport("invalid response from PinShell")
        }
    }

    /// listen：返回保持打开的 fd 与订阅响应。
    static func openListenStream(launchIfNeeded: Bool = true) throws -> (fd: Int32, response: ControlResponse) {
        let fd = try openConnection(launchIfNeeded: launchIfNeeded)
        do {
            let request = ControlRequest(cmd: "listen")
            try writeAll(fd: fd, data: ControlWire.encodeLine(request))
            guard let line = try readLine(fd: fd, timeout: 5) else {
                throw ControlClientError.transport("connection closed before subscription")
            }
            let response = try ControlWire.decodeLine(line, as: ControlResponse.self)
            guard response.ok else {
                throw ControlClientError.transport(response.error?.message ?? "listen rejected")
            }
            return (fd, response)
        } catch {
            closeConnection(fd)
            throw error
        }
    }

    /// 关闭连接并丢弃该 fd 的残留读缓冲。fd 会被系统复用，必须成对清理。
    static func closeConnection(_ fd: Int32) {
        readBufferLock.lock()
        readBuffers.removeValue(forKey: fd)
        readBufferLock.unlock()
        Darwin.close(fd)
    }

    // MARK: - 连接与启动

    /// 优先连接现有 App；未运行则（可选）拉起并等待 socket，直接返回可用连接。
    private static func openConnection(launchIfNeeded: Bool) throws -> Int32 {
        if let fd = UnixSocket.connect(path: ControlEndpoint.socketPath()) {
            return fd
        }

        guard launchIfNeeded else {
            throw ControlClientError.appUnavailable("PinShell is not running")
        }

        launchApp()

        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            if let fd = UnixSocket.connect(path: ControlEndpoint.socketPath()) {
                return fd
            }
            usleep(100_000)
        }

        if isAppRunning() {
            throw ControlClientError.appUnavailable(
                "PinShell is running but its control socket is unavailable (restart the app to enable CLI control)"
            )
        }
        throw ControlClientError.appUnavailable("PinShell did not start in time")
    }

    private static func launchApp() {
        if let appURL = registeredAppURL() {
            // 用 /usr/bin/open 而不是 NSWorkspace：MCP 工具现在跑在后台队列上，
            // 这里不能依赖调用线程的 run loop。 -g 保持不抢焦点。
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-g", appURL.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            return
        }

        // 裸二进制开发模式：以无参数方式启动自身（宿主模式）
        let executable = Bundle.main.executableURL
            ?? URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        let process = Process()
        process.executableURL = executable
        process.arguments = []
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    private static func registeredAppURL() -> URL? {
        let bundle = Bundle.main.bundleURL
        if bundle.pathExtension == "app" { return bundle }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.pinshell.app")
    }

    private static func isAppRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.pinshell.app").isEmpty
    }

    // MARK: - I/O

    static func writeAll(fd: Int32, data: Data) throws {
        var offset = 0
        while offset < data.count {
            let written = data.withUnsafeBytes { buffer -> Int in
                guard let base = buffer.baseAddress else { return 0 }
                return write(fd, base.advanced(by: offset), data.count - offset)
            }
            if written < 0 {
                if errno == EINTR { continue }
                throw ControlClientError.transport(String(cString: strerror(errno)))
            }
            offset += written
        }
    }

    // 每个 fd 的增量读缓冲：一次 read 可能包含多行，不能只返回第一行就丢弃剩余字节。
    private static let readBufferLock = NSLock()
    private static var readBuffers: [Int32: Data] = [:]

    /// 读取一行（不含换行）；timeout == nil 时无限等待。
    /// 返回 nil 表示对端关闭。
    static func readLine(fd: Int32, timeout: TimeInterval?) throws -> Data? {
        let deadline = timeout.map { Date().addingTimeInterval($0) }

        while true {
            readBufferLock.lock()
            if var buffer = readBuffers[fd], let newline = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[buffer.startIndex..<newline])
                buffer.removeSubrange(buffer.startIndex...newline)
                readBuffers[fd] = buffer
                readBufferLock.unlock()
                return line
            }
            readBufferLock.unlock()

            let pollMillis: Int32
            if let deadline {
                let remaining = deadline.timeIntervalSinceNow
                if remaining <= 0 { throw ControlClientError.timeout }
                pollMillis = Int32(min(remaining, 1.0) * 1000)
            } else {
                pollMillis = 1000
            }

            var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, pollMillis)
            if ready < 0 {
                if errno == EINTR { continue }
                throw ControlClientError.transport(String(cString: strerror(errno)))
            }
            if ready == 0 { continue }

            var chunk = [UInt8](repeating: 0, count: 16 * 1024)
            let count = read(fd, &chunk, chunk.count)
            if count == 0 { return nil }
            if count < 0 {
                if errno == EINTR { continue }
                throw ControlClientError.transport(String(cString: strerror(errno)))
            }

            readBufferLock.lock()
            var buffer = readBuffers[fd] ?? Data()
            buffer.append(contentsOf: chunk[0..<count])
            if buffer.count > ControlProtocolConstants.maxLineBytes {
                readBufferLock.unlock()
                throw ControlClientError.transport("response exceeds size limit")
            }
            readBuffers[fd] = buffer
            readBufferLock.unlock()
        }
    }
}
