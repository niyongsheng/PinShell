import Foundation
import Darwin
import PinShellCore

/// 本机控制通道服务端：Unix domain socket + 行分隔 JSON。
/// 所有请求回主线程交给 ControlHost；事件广播给已 `listen` 的客户端。
final class ControlServer {
    /// 在主线程回调（ControlHost 设置）
    var onRequest: ((ControlRequest, ControlConnection) -> Void)?

    private let queue = DispatchQueue(label: "PinShell.ControlServer")
    private let socketPath: String
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var clients: [Int32: ControlConnection] = [:]

    init(socketURL: URL = ControlEndpoint.socketURL()) {
        self.socketPath = socketURL.path
    }

    deinit { stop() }

    /// 返回 false 表示已有实例持有 socket（单实例锁）。
    func start() -> Bool {
        let directory = (socketPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: directory,
                                                 withIntermediateDirectories: true)
        chmod(directory, 0o700)

        if FileManager.default.fileExists(atPath: socketPath) {
            if let probe = UnixSocket.connect(path: socketPath) {
                Darwin.close(probe)   // 已有实例在服务
                return false
            }
            unlink(socketPath) // 残留 socket
        }

        guard let fd = UnixSocket.bindAndListen(path: socketPath) else { return false }
        listenFD = fd
        chmod(socketPath, 0o600)

        // accept 循环：监听 fd 非阻塞，避免 read source 误唤醒时卡死
        let flags = fcntl(fd, F_GETFL, 0)
        if flags >= 0 { _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK) }

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptClients() }
        source.resume()
        acceptSource = source
        return true
    }

    func stop() {
        queue.sync {
            acceptSource?.cancel()
            acceptSource = nil
            if listenFD >= 0 {
                Darwin.close(listenFD)
                listenFD = -1
            }
            for connection in clients.values { connection.close() }
            clients.removeAll()
            unlink(socketPath)
        }
    }

    func broadcast(_ event: ControlEvent) {
        queue.async { [weak self] in
            guard let self, !self.clients.isEmpty,
                  let data = try? ControlWire.encodeLine(event) else { return }
            for connection in self.clients.values {
                connection.send(eventData: data)
            }
        }
    }

    fileprivate func dispatch(_ request: ControlRequest, from connection: ControlConnection) {
        DispatchQueue.main.async { [weak self] in
            self?.onRequest?(request, connection)
        }
    }

    fileprivate func remove(_ connection: ControlConnection) {
        queue.async { [weak self] in
            self?.clients.removeValue(forKey: connection.fd)
        }
    }

    private func acceptClients() {
        while true {
            let clientFD = accept(listenFD, nil, nil)
            guard clientFD >= 0 else { break }
            UnixSocket.noSigPipe(clientFD)

            // 客户端写阻塞最多 5s：慢速 listen 客户端不会拖死服务队列
            var timeout = timeval(tv_sec: 5, tv_usec: 0)
            _ = setsockopt(clientFD, SOL_SOCKET, SO_SNDTIMEO, &timeout,
                           socklen_t(MemoryLayout<timeval>.size))

            let connection = ControlConnection(fd: clientFD, server: self)
            clients[clientFD] = connection
            connection.start()
        }
    }
}

/// 单个 CLI 客户端连接；读写都在独立串行队列上，避免多客户端互相阻塞。
final class ControlConnection {
    let fd: Int32
    private weak var server: ControlServer?
    private let queue: DispatchQueue

    private var readSource: DispatchSourceRead?
    private var framer = LineFramer()
    private var isSubscribed = false
    private var isClosed = false
    private var pending: [Data] = []
    private var pendingBytes = 0

    private static let maxPendingBytes = 4 * 1024 * 1024

    fileprivate init(fd: Int32, server: ControlServer) {
        self.fd = fd
        self.server = server
        self.queue = DispatchQueue(label: "PinShell.ControlClient.\(fd)")
    }

    fileprivate func start() {
        queue.async { [weak self] in
            guard let self else { return }
            let source = DispatchSource.makeReadSource(fileDescriptor: self.fd, queue: self.queue)
            source.setEventHandler { [weak self] in self?.readAvailable() }
            source.setCancelHandler { Darwin.close(self.fd) }
            self.readSource = source
            source.resume()
        }
    }

    func subscribe() {
        queue.async { [weak self] in self?.isSubscribed = true }
    }

    func send(_ response: ControlResponse) {
        guard let data = try? ControlWire.encodeLine(response) else { return }
        queue.async { [weak self] in
            guard let self, !self.isClosed else { return }
            self.enqueueLocked(data)
        }
    }

    /// 事件已由服务端统一编码，所有订阅者共享同一份 Data。
    func send(eventData: Data) {
        queue.async { [weak self] in
            guard let self, !self.isClosed, self.isSubscribed else { return }
            self.enqueueLocked(eventData)
        }
    }

    func close() {
        queue.async { [weak self] in self?.closeLocked() }
    }

    // MARK: - 队列内状态

    private func readAvailable() {
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        let count = read(fd, &buffer, buffer.count)
        guard count > 0 else {
            closeLocked()
            return
        }

        do {
            for line in try framer.append(Data(buffer[0..<count])) {
                do {
                    let request = try ControlWire.decodeLine(line, as: ControlRequest.self)
                    server?.dispatch(request, from: self)
                } catch {
                    sendLocked(.failure(id: "", code: "bad_request",
                                        message: "invalid JSON request"))
                }
            }
        } catch {
            sendLocked(.failure(id: "", code: "line_too_long",
                                message: "message exceeds \(ControlProtocolConstants.maxLineBytes) bytes"))
            closeLocked()
        }
    }

    private func sendLocked(_ response: ControlResponse) {
        guard let data = try? ControlWire.encodeLine(response) else { return }
        enqueueLocked(data)
    }

    private func enqueueLocked(_ data: Data) {
        guard !isClosed else { return }
        guard pendingBytes + data.count <= Self.maxPendingBytes else {
            closeLocked()
            return
        }
        pending.append(data)
        pendingBytes += data.count
        flushLocked()
    }

    private func flushLocked() {
        while let data = pending.first {
            let written = data.withUnsafeBytes { buffer -> Int in
                guard let base = buffer.baseAddress else { return 0 }
                return write(fd, base, data.count)
            }
            if written < 0 {
                if errno == EINTR { continue }
                closeLocked()
                return
            }
            if written < data.count {
                pending[0] = data.subdata(in: written..<data.count)
                pendingBytes = pending.reduce(0) { $0 + $1.count }
                return
            }
            pendingBytes -= data.count
            pending.removeFirst()
        }
    }

    private func closeLocked() {
        guard !isClosed else { return }
        isClosed = true
        if let source = readSource {
            source.cancel()
            readSource = nil
        } else {
            Darwin.close(fd)
        }
        pending.removeAll()
        pendingBytes = 0
        server?.remove(self)
    }
}
