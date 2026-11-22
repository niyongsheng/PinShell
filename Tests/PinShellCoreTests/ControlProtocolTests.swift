import XCTest
@testable import PinShellCore

final class ControlProtocolTests: XCTestCase {
    func testRequestRoundTrip() throws {
        let request = ControlRequest(id: "r1", cmd: "show", args: [
            "path": .string("/tmp/panel.html"),
            "size": .string("240x80"),
            "watch": .bool(true)
        ])
        let data = try ControlWire.encodeLine(request)
        XCTAssertEqual(data.last, 0x0A)

        let decoded = try ControlWire.decodeLine(Data(data.dropLast()), as: ControlRequest.self)
        XCTAssertEqual(decoded, request)
    }

    func testResponseRoundTrip() throws {
        let response = ControlResponse.success(id: "r1", result: .object([
            "file": .string("panel.html"),
            "frame": .array([.number(10), .number(20), .number(240), .number(80)])
        ]))
        let data = try ControlWire.encoder.encode(response)
        let decoded = try ControlWire.decoder.decode(ControlResponse.self, from: data)
        XCTAssertEqual(decoded, response)
        XCTAssertNil(decoded.error)
    }

    func testEventOmitsNilFields() throws {
        let event = ControlEvent.emit(name: "submit",
                                      data: .object(["text": .string("hello")]))
        let data = try ControlWire.encoder.encode(event)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["event"] as? String, "emit")
        XCTAssertEqual(object["name"] as? String, "submit")
        XCTAssertNil(object["message"])
    }

    func testJSONValueHandlesArbitraryBodies() {
        XCTAssertEqual(JSONValue(any: NSNull()), .null)
        XCTAssertEqual(JSONValue(any: true), .bool(true))
        XCTAssertEqual(JSONValue(any: 42), .number(42))
        XCTAssertEqual(JSONValue(any: "hi"), .string("hi"))
        XCTAssertEqual(JSONValue(any: [1, "two"]),
                       .array([.number(1), .string("two")]))
        XCTAssertEqual(JSONValue(any: ["a": 1]), .object(["a": .number(1)]))
    }

    func testNumberOneIsNotCoercedToBool() {
        // WKScriptMessage 的数字会以 NSNumber 传入；NSNumber(1) 也能 as? Bool
        XCTAssertEqual(JSONValue(any: NSNumber(value: 1)), .number(1))
        XCTAssertEqual(JSONValue(any: NSNumber(value: 0)), .number(0))
        XCTAssertEqual(JSONValue(any: NSNumber(value: true)), .bool(true))
        XCTAssertEqual(JSONValue(any: NSNumber(value: 3.5)), .number(3.5))
    }

    func testLineFramerSplitsAcrossChunks() throws {
        var framer = LineFramer(maxLineBytes: 64)
        XCTAssertTrue(try framer.append(Data("{\"a\":1}".utf8)).isEmpty)
        let lines = try framer.append(Data("\n{\"b\":2}\n".utf8))
        XCTAssertEqual(lines.map { String(decoding: $0, as: UTF8.self) },
                       ["{\"a\":1}", "{\"b\":2}"])
    }

    func testLineFramerRejectsOversizedLine() {
        var framer = LineFramer(maxLineBytes: 8)
        XCTAssertThrowsError(try framer.append(Data("123456789".utf8))) { error in
            XCTAssertEqual(error as? LineFramerError, .oversizedLine(maxBytes: 8))
        }
    }

    // MARK: - 事件 envelope / 事件日志

    func testEventTypeFollowsNamePrefix() {
        XCTAssertEqual(ControlEvent.emit(name: "submit", data: .null).type, "ui")
        XCTAssertEqual(ControlEvent.emit(name: "ui:submit", data: .null).type, "ui")
        XCTAssertEqual(ControlEvent.emit(name: "pet:tap", data: .null).type, "pet")
        XCTAssertEqual(ControlEvent.emit(name: "system:stats", data: .null).type, "system")
        XCTAssertEqual(ControlEvent.stateSnapshot(.object([:])).type, "state")
        XCTAssertEqual(ControlEvent.loaded(file: "/tmp/a.html", url: "file:///tmp/a.html").type,
                       "lifecycle")
    }

    func testEventLogStampsSequenceAndSupportsCursor() {
        let log = EventLog(epoch: "epoch-1", capacity: 10)
        let first = log.append(.emit(name: "ui:ready", data: .object([:])))
        let second = log.append(.emit(name: "ui:submit", data: .object(["ok": .bool(true)])))

        XCTAssertEqual(first.seq, 1)
        XCTAssertEqual(second.seq, 2)
        XCTAssertEqual(first.epoch, "epoch-1")
        XCTAssertNotNil(first.ts)

        let page = log.query(since: 0, epoch: "epoch-1", limit: 1)
        XCTAssertEqual(page.events.map(\.seq), [1])
        XCTAssertEqual(page.next, 1)
        XCTAssertTrue(page.more)
        XCTAssertEqual(page.dropped, 0)

        let rest = log.query(since: page.next, epoch: "epoch-1", limit: 10)
        XCTAssertEqual(rest.events.map(\.seq), [2])
        XCTAssertEqual(rest.next, 2)
        XCTAssertFalse(rest.more)
    }

    func testEventLogFiltersByTypeAndName() {
        let log = EventLog(epoch: "e", capacity: 10)
        log.append(.emit(name: "ui:ready", data: .null))
        log.append(.emit(name: "pet:tap", data: .null))
        log.append(.stateSnapshot(.object(["phase": .string("ready")])))

        let ui = log.query(since: 0, epoch: "e", types: ["ui"], limit: 10)
        XCTAssertEqual(ui.events.map(\.name), ["ui:ready"])

        let pet = log.query(since: 0, epoch: "e", names: ["pet:tap"], limit: 10)
        XCTAssertEqual(pet.events.map(\.name), ["pet:tap"])

        let state = log.query(since: 0, epoch: "e", types: ["state"], limit: 10)
        XCTAssertEqual(state.events.map(\.name), ["state:snapshot"])
    }

    func testEventLogEpochMismatchResetsCursor() {
        let log = EventLog(epoch: "new-epoch", capacity: 10)
        log.append(.emit(name: "ui:ready", data: .null))
        log.append(.emit(name: "ui:submit", data: .null))

        let batch = log.query(since: 99, epoch: "old-epoch", limit: 10)
        XCTAssertTrue(batch.reset)
        XCTAssertEqual(batch.epoch, "new-epoch")
        XCTAssertEqual(batch.events.map(\.seq), [1, 2])
        XCTAssertEqual(batch.next, 2)
    }

    func testEventLogReportsDroppedEvents() {
        let log = EventLog(epoch: "e", capacity: 2)
        log.append(.emit(name: "ui:one", data: .null))
        log.append(.emit(name: "ui:two", data: .null))
        log.append(.emit(name: "ui:three", data: .null))

        let batch = log.query(since: 0, epoch: "e", limit: 10)
        XCTAssertEqual(batch.events.map(\.seq), [2, 3])
        XCTAssertEqual(batch.dropped, 1)
    }

    func testEventLogTracksLatestSessionAndClearsItOnClose() {
        let log = EventLog(epoch: "e", capacity: 10)

        var started = ControlEvent.sessionStarted(previous: nil)
        started.session = "s1"
        log.append(started)

        var ready = ControlEvent.emit(name: "ui:ready", data: .null)
        ready.session = "s1"
        log.append(ready)

        let open = log.query(since: 0, epoch: "e", limit: 10)
        XCTAssertEqual(open.latestSession, "s1")
        XCTAssertEqual(open.latestSeq, 2)

        var ended = ControlEvent.sessionEnded()
        ended.session = "s1"
        log.append(ended)

        let closed = log.query(since: 0, epoch: "e", limit: 10)
        XCTAssertNil(closed.latestSession)
        XCTAssertEqual(closed.latestSeq, 3)
    }

    func testStateDeltaCarriesOnlyPatch() {
        let event = ControlEvent.stateDelta(.object(["phase": .string("submitted")]))
        XCTAssertEqual(event.name, "state:delta")
        XCTAssertEqual(event.type, "state")
        XCTAssertEqual(event.data?["patch"]?["phase"]?.stringValue, "submitted")
        XCTAssertNil(event.data?["state"])
    }

    func testStampedEventEncodesCursorFields() throws {
        let log = EventLog(epoch: "e", capacity: 10)
        let event = log.append(.emit(name: "ui:submit", data: .object([:])))
        let data = try ControlWire.encoder.encode(event)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["seq"] as? Int, 1)
        XCTAssertEqual(object["epoch"] as? String, "e")
        XCTAssertEqual(object["type"] as? String, "ui")
        XCTAssertEqual(object["name"] as? String, "ui:submit")
        XCTAssertNotNil(object["ts"] as? Double)
    }

    // MARK: - Merge patch

    func testMergePatchFollowsRFC7386() {
        let base: JSONValue = .object([
            "a": .number(1),
            "b": .object(["c": .number(2), "d": .number(3)])
        ])
        let patch: JSONValue = .object([
            "b": .object(["c": .null, "e": .number(4)]),
            "f": .number(5)
        ])

        XCTAssertEqual(base.applyingMergePatch(patch), .object([
            "a": .number(1),
            "b": .object(["d": .number(3), "e": .number(4)]),
            "f": .number(5)
        ]))
        XCTAssertEqual(JSONValue.object(["a": .number(1)])
            .applyingMergePatch(.array([.number(2)])), .array([.number(2)]))
        XCTAssertEqual(JSONValue.object(["a": .number(1)]).applyingMergePatch(.null), .null)
    }
}
