import Foundation
import PinShellCore

/// 后台订阅 `listen`，把页面事件放入本地环形缓冲。
///
/// 事件语义：
/// - 事件带 `seq` / `epoch`，`poll` 按游标增量读取；
/// - 断线重连时通过控制通道的 `events` 命令按游标补齐缺口；
/// - 等待可被 `notifications/cancelled` 唤醒；
/// - 返回的批次带 `connected` / `dropped` / `more` / `skipped` 等元数据。
final class MCPEventStream {
    struct Batch {
        var epoch: String
        var events: [ControlEvent]
        var next: Int
        var dropped: Int
        var more: Bool
        var cancelled: Bool
        var connected: Bool
        var skipped: Int
        var session: String?
        var reset: Bool

        var jsonValue: JSONValue {
            .object([
                "epoch": .string(epoch),
                "events": .array(events.map(\.jsonValue)),
                "next": .number(Double(next)),
                "dropped": .number(Double(dropped)),
                "more": .bool(more),
                "cancelled": .bool(cancelled),
                "connected": .bool(connected),
                "skipped": .number(Double(skipped)),
                "session": session.map(JSONValue.string) ?? .null,
                "reset": .bool(reset)
            ])
        }
    }

    private struct Query {
        var events: [ControlEvent]
        var next: Int
        var dropped: Int
        var more: Bool
        var skipped: Int
    }

    private let condition = NSCondition()
    private let maxEvents = 1000
    private var events: [ControlEvent] = []
    private var seqs = Set<Int>()
    private var started = false
    private var epoch = ""
    /// 已交付给 agent 的游标（poll/await 默认从这里继续）。
    private var lastSeq = 0
    /// 本地缓冲里见过的最大 seq（断线重连从这里补齐）。
    private var lastBufferedSeq = 0
    private var evictedThrough = 0
    private var connected = false
    private var waitGeneration = 0

    // MARK: - 查询

    /// 在 MCP server 启动时就连上 App，避免 page load 到第一次 poll 之间的事件丢失。
    func start() {
        startIfNeeded()
    }

    func poll(since: Int?,
              epoch requestedEpoch: String?,
              wait: TimeInterval,
              types: Set<String>?,
              names: Set<String>?,
              limit: Int) -> Batch {
        startIfNeeded()

        condition.lock()
        defer { condition.unlock() }

        let generation = waitGeneration
        let deadline = Date().addingTimeInterval(max(wait, 0))

        while true {
            // 传了 epoch 且与当前 App 不一致：游标失效，从新缓冲开头重放。
            // since 省略时每轮重新读取 lastSeq：并发 poll 中先返回的调用会推进游标，
            // 后醒来的调用不会重复交付同一批事件。
            let reset = requestedEpoch.map { !epoch.isEmpty && $0 != epoch } ?? false
            if reset {
                // 调用方的游标属于另一个 epoch：默认游标也回到起点。
                lastSeq = 0
            }
            let cursor = reset ? 0 : max(since ?? lastSeq, 0)

            if generation != waitGeneration {
                let query = queryLocked(since: cursor, types: types, names: names, limit: limit)
                return batch(query, cancelled: true, reset: reset)
            }

            let query = queryLocked(since: cursor, types: types, names: names, limit: limit)
            if !query.events.isEmpty {
                if let last = query.events.last?.seq {
                    lastSeq = max(lastSeq, last)
                }
                return batch(query, cancelled: false, reset: reset)
            }

            if wait <= 0 { return batch(query, cancelled: false, reset: reset) }

            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { return batch(query, cancelled: false, reset: reset) }
            condition.wait(until: deadline)
        }
    }

    /// 取消所有正在等待的 poll/await（MCP `notifications/cancelled`）。
    func cancelWaiters() {
        condition.lock()
        waitGeneration += 1
        condition.broadcast()
        condition.unlock()
    }

    private func queryLocked(since: Int,
                             types: Set<String>?,
                             names: Set<String>?,
                             limit: Int) -> Query {
        let maxCount = max(limit, 1)
        var matches: [ControlEvent] = []

        for event in events {
            guard let seq = event.seq, seq > since else { continue }
            guard EventLog.matches(event, types: types, names: names) else { continue }
            matches.append(event)
            if matches.count > maxCount { break }
        }

        let more = matches.count > maxCount
        let returned = Array(matches.prefix(maxCount))
        let next = returned.last?.seq ?? since
        let skipped = events.reduce(0) { count, event in
            guard let seq = event.seq, seq > since, seq <= next else { return count }
            return EventLog.matches(event, types: types, names: names) ? count : count + 1
        }

        return Query(events: returned,
                     next: next,
                     dropped: max(0, evictedThrough - since),
                     more: more,
                     skipped: skipped)
    }

    private func batch(_ query: Query, cancelled: Bool, reset: Bool) -> Batch {
        Batch(epoch: epoch,
              events: query.events,
              next: query.next,
              dropped: query.dropped,
              more: query.more,
              cancelled: cancelled,
              connected: connected,
              skipped: query.skipped,
              session: query.events.last?.session ?? events.last?.session,
              reset: reset)
    }

    // MARK: - 订阅

    private func startIfNeeded() {
        condition.lock()
        if started {
            condition.unlock()
            return
        }
        started = true
        condition.unlock()

        let thread = Thread { [weak self] in self?.run() }
        thread.name = "PinShell.MCP.Events"
        thread.start()
    }

    private func run() {
        while true {
            syncInitialSession()
            do {
                // 事件监听不负责拉起 App：App 由实际工具调用启动。
                let (fd, _) = try ControlClient.openListenStream(launchIfNeeded: false)
                defer { ControlClient.closeConnection(fd) }
                setConnected(true)
                backfill()
                while let line = try ControlClient.readLine(fd: fd, timeout: nil) {
                    guard let event = try? ControlWire.decodeLine(line, as: ControlEvent.self) else {
                        continue
                    }
                    ingest(event)
                }
            } catch {
                // App 未运行/退出：稍后重试；重连后按游标补齐。
            }
            setConnected(false)
            Thread.sleep(forTimeInterval: 1)
        }
    }

    private func setConnected(_ value: Bool) {
        condition.lock()
        connected = value
        condition.broadcast()
        condition.unlock()
    }

    /// 首次连接时先取 App 的当前 session，只回放这个 session 的事件。
    ///
    /// 这样既能补上 `listen` 订阅建立前丢掉的 `ui:ready` / `state:snapshot`，
    /// 又不会把上一个 agent 会话或手工面板的旧事件带进来。
    private func syncInitialSession() {
        condition.lock()
        let needsSync = epoch.isEmpty
        condition.unlock()
        guard needsSync else { return }

        let args: [String: JSONValue] = [
            "since": .number(0),
            "limit": .number(1000)
        ]
        guard let response = try? ControlClient.request(ControlRequest(cmd: "events", args: args),
                                                        timeout: 10,
                                                        launchIfNeeded: false),
              response.ok,
              let result = response.result else { return }

        let batchEpoch = result["epoch"]?.stringValue ?? ""
        let latestSession = result["latestSession"]?.stringValue
        let replayed = result["events"]?.arrayValue ?? []

        condition.lock()
        defer { condition.unlock() }
        guard epoch.isEmpty else { return }
        if !batchEpoch.isEmpty {
            epoch = batchEpoch
        }
        // 没有当前 session（面板未打开/已关闭）：从“现在”开始，不回放旧事件。
        guard let latestSession else {
            let latest = result["latest"]?.intValue ?? 0
            lastSeq = max(lastSeq, latest)
            lastBufferedSeq = max(lastBufferedSeq, latest)
            condition.broadcast()
            return
        }
        var firstCurrentSeq: Int?
        for event in Self.decodeEvents(replayed) {
            if event.session != latestSession { continue }
            if firstCurrentSeq == nil { firstCurrentSeq = event.seq }
            ingestLocked(event)
        }
        // 默认游标从当前 session 的第一条事件开始，避免把上一个 session 的旧事件
        // 当成新事件交给 agent；显式传 since: 0 仍可回放全部缓冲。
        if lastSeq == 0, let first = firstCurrentSeq {
            lastSeq = max(0, first - 1)
        }
        condition.broadcast()
    }

    /// 连接建立后向 App 要回断线期间的事件。epoch 不一致时 App 会返回 reset。
    private func backfill() {
        condition.lock()
        let since = lastBufferedSeq
        let currentEpoch = epoch.isEmpty ? nil : epoch
        condition.unlock()

        guard let currentEpoch else { return }

        let args: [String: JSONValue] = [
            "since": .number(Double(since)),
            "epoch": .string(currentEpoch),
            "limit": .number(1000)
        ]

        guard let response = try? ControlClient.request(ControlRequest(cmd: "events", args: args),
                                                        timeout: 10,
                                                        launchIfNeeded: false),
              response.ok,
              let result = response.result else { return }

        let batchEpoch = result["epoch"]?.stringValue ?? ""
        let reset = result["reset"]?.boolValue ?? false
        let dropped = result["dropped"]?.intValue ?? 0
        let replayed = result["events"]?.arrayValue ?? []

        condition.lock()
        defer { condition.unlock() }

        if reset || (!batchEpoch.isEmpty && batchEpoch != epoch) {
            events.removeAll()
            seqs.removeAll()
            lastSeq = 0
            lastBufferedSeq = 0
            evictedThrough = 0
            epoch = batchEpoch
        } else if epoch.isEmpty, !batchEpoch.isEmpty {
            epoch = batchEpoch
        } else if !reset, dropped > 0 {
            evictedThrough = max(evictedThrough, since + dropped)
        }

        for event in Self.decodeEvents(replayed) {
            ingestLocked(event)
        }
        condition.broadcast()
    }

    /// 控制通道回放的是 JSONValue 数组；一次解码成事件，避免逐条编解码。
    private static func decodeEvents(_ values: [JSONValue]) -> [ControlEvent] {
        guard !values.isEmpty,
              let data = try? ControlWire.encoder.encode(JSONValue.array(values)),
              let events = try? ControlWire.decoder.decode([ControlEvent].self, from: data)
        else { return [] }
        return events
    }

    private func ingest(_ event: ControlEvent) {
        condition.lock()
        ingestLocked(event)
        condition.broadcast()
        condition.unlock()
    }

    private func ingestLocked(_ event: ControlEvent) {
        if let eventEpoch = event.epoch, !eventEpoch.isEmpty {
            if epoch.isEmpty {
                epoch = eventEpoch
            } else if eventEpoch != epoch {
                events.removeAll()
                seqs.removeAll()
                lastSeq = 0
                lastBufferedSeq = 0
                evictedThrough = 0
                epoch = eventEpoch
            }
        }

        guard let seq = event.seq else {
            events.append(event)
            return
        }
        guard !seqs.contains(seq) else { return }

        // 新 session 开始时，如果 agent 还没有交付过事件，把默认游标推到
        // session:started 之前，避免第一次 poll 拿到上一个面板的旧交互。
        if event.name == "session:started", lastSeq == 0, seq > 1 {
            lastSeq = seq - 1
        }

        events.append(event)
        seqs.insert(seq)
        lastBufferedSeq = max(lastBufferedSeq, seq)

        if events.count > 1,
           let previous = events[events.count - 2].seq,
           previous > seq {
            events.sort { ($0.seq ?? 0) < ($1.seq ?? 0) }
        }

        while events.count > maxEvents {
            let evicted = events.removeFirst()
            if let evictedSeq = evicted.seq {
                seqs.remove(evictedSeq)
                evictedThrough = max(evictedThrough, evictedSeq)
            }
        }
    }
}
