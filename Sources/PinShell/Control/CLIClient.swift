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
                        timeout: TimeInterval = 10) throws -> ControlResponse {
        let fd = try openConnectionLaunchingIfNeeded()
        defer { close(fd) }

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
    static func openListenStream() throws -> (fd: Int32, response: ControlResponse) {
        let fd = try openConnectionLaunchingIfNeeded()
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
            close(fd)
            throw error
        }
    }

    // MARK: - 连接与启动

    /// 优先连接现有 App；未运行则拉起并等待 socket，直接返回可用连接。
    private static func openConnectionLaunchingIfNeeded() throws -> Int32 {
        if let fd = UnixSocket.connect(path: ControlEndpoint.socketPath()) {
            return fd
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
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            var finished = false
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, _ in
                finished = true
            }
            // CLI 没有主 run loop；短暂泵一下，让 LaunchServices 完成请求
            let deadline = Date().addingTimeInterval(2)
            while !finished && Date() < deadline {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
            }
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

    /// 读取一行（不含换行）；timeout == nil 时无限等待。
    /// 返回 nil 表示对端关闭。
    static func readLine(fd: Int32, timeout: TimeInterval?) throws -> Data? {
        var buffer = Data()
        let deadline = timeout.map { Date().addingTimeInterval($0) }

        while true {
            if let newline = buffer.firstIndex(of: 0x0A) {
                return Data(buffer[buffer.startIndex..<newline])
            }

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
            buffer.append(contentsOf: chunk[0..<count])
            if buffer.count > ControlProtocolConstants.maxLineBytes {
                throw ControlClientError.transport("response exceeds size limit")
            }
        }
    }
}
