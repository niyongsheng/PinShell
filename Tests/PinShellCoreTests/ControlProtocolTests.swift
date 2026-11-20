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
}
