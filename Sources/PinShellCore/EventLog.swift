import Foundation

/// 一次事件查询的结果。`next` 是下一次查询应使用的游标；`dropped` 表示
/// `since` 与缓冲区最旧事件之间已经缺失的事件数（至少）。
public struct EventLogBatch: Equatable, Sendable {
    public var epoch: String
    public var events: [ControlEvent]
    public var next: Int
    public var dropped: Int
    public var more: Bool
    public var reset: Bool
    /// 环形缓冲当前最大 seq（不受查询游标/过滤影响），MCP 首次连接用它定位“现在”。
    public var latestSeq: Int
    /// 环形缓冲里最新事件所属的 session；MCP 首次连接只回放这个 session 的事件。
    public var latestSession: String?

    public init(epoch: String,
                events: [ControlEvent],
                next: Int,
                dropped: Int,
                more: Bool,
                reset: Bool,
                latestSeq: Int = 0,
                latestSession: String? = nil) {
        self.epoch = epoch
        self.events = events
        self.next = next
        self.dropped = dropped
        self.more = more
        self.reset = reset
        self.latestSeq = latestSeq
        self.latestSession = latestSession
    }

    public var jsonValue: JSONValue {
        .object([
            "epoch": .string(epoch),
            "events": .array(events.map(\.jsonValue)),
            "next": .number(Double(next)),
            "dropped": .number(Double(dropped)),
            "more": .bool(more),
            "reset": .bool(reset),
            "latest": .number(Double(latestSeq)),
            "latestSession": latestSession.map(JSONValue.string) ?? .null
        ])
    }
}

/// App 侧的事件环形缓冲区：给事件盖 `seq` / `epoch` / `ts`，并支持按游标重放。
///
/// `epoch` 每次 App 启动重新生成，避免重启后旧游标误读新序号。查询到不同 epoch
/// 时忽略 `since` 并从当前缓冲区开头重放（`reset: true`）。
/// 非线程安全，调用方需串行访问（`ControlServer` 的串行队列）。
public final class EventLog {
    public let epoch: String
    private var events: [ControlEvent] = []
    private var nextSeq = 1
    private var evictedThrough = 0
    private let capacity: Int

    public init(epoch: String = UUID().uuidString, capacity: Int = 1000) {
        self.epoch = epoch
        self.capacity = max(capacity, 1)
    }

    @discardableResult
    public func append(_ event: ControlEvent) -> ControlEvent {
        var stamped = event
        stamped.epoch = epoch
        stamped.seq = nextSeq
        if stamped.ts == nil {
            stamped.ts = Date().timeIntervalSince1970
        }
        nextSeq += 1
        events.append(stamped)
        while events.count > capacity {
            if let seq = events.removeFirst().seq {
                evictedThrough = max(evictedThrough, seq)
            }
        }
        return stamped
    }

    public var latest: ControlEvent? { events.last }

    public func query(since: Int,
                      epoch clientEpoch: String?,
                      types: Set<String>? = nil,
                      names: Set<String>? = nil,
                      limit: Int = 200) -> EventLogBatch {
        let reset = clientEpoch.map { $0 != epoch } ?? false
        let cursor = reset ? 0 : max(since, 0)
        let maxCount = max(limit, 1)

        var matches: [ControlEvent] = []
        for event in events {
            guard let seq = event.seq, seq > cursor else { continue }
            guard Self.matches(event, types: types, names: names) else { continue }
            matches.append(event)
            if matches.count > maxCount { break }
        }

        let more = matches.count > maxCount
        let returned = Array(matches.prefix(maxCount))
        let next = returned.last?.seq ?? cursor
        let dropped = reset ? 0 : max(0, evictedThrough - cursor)

        let latest = events.last
        // 面板已关闭（session:ended）时没有“当前 session”，MCP 首次连接不回放旧交互。
        let latestSession = latest?.name == "session:ended" ? nil : latest?.session
        return EventLogBatch(epoch: epoch,
                             events: returned,
                             next: next,
                             dropped: dropped,
                             more: more,
                             reset: reset,
                             latestSeq: latest?.seq ?? 0,
                             latestSession: latestSession)
    }

    public static func matches(_ event: ControlEvent,
                               types: Set<String>?,
                               names: Set<String>?) -> Bool {
        if let types, !types.isEmpty {
            guard let type = event.type, types.contains(type) else { return false }
        }
        if let names, !names.isEmpty {
            guard let name = event.name, names.contains(name) else { return false }
        }
        return true
    }
}
