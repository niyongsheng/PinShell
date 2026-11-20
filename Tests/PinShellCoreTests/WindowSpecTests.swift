import XCTest
@testable import PinShellCore

final class WindowSpecTests: XCTestCase {
    private let screen = WindowFrame(x: 0, y: 0, width: 1000, height: 800)

    func testParsesSizeVariants() {
        XCTAssertEqual(WindowSize.parse("240x80"), WindowSize(width: 240, height: 80))
        XCTAssertEqual(WindowSize.parse("240*80"), WindowSize(width: 240, height: 80))
        XCTAssertEqual(WindowSize.parse("240, 80"), WindowSize(width: 240, height: 80))
        XCTAssertNil(WindowSize.parse("240"))
        XCTAssertNil(WindowSize.parse("0x80"))
    }

    func testParsesPositionVariants() {
        XCTAssertEqual(WindowPosition.parse("bottom-right"), .anchor(.bottomRight))
        XCTAssertEqual(WindowPosition.parse("top_left"), .anchor(.topLeft))
        XCTAssertEqual(WindowPosition.parse("120,240"), .absolute(x: 120, y: 240))
        XCTAssertEqual(WindowPosition.parse("120 240"), .absolute(x: 120, y: 240))
        XCTAssertNil(WindowPosition.parse("nowhere"))
    }

    func testSizeOnlyKeepsCurrentOrigin() {
        let current = WindowFrame(x: 100, y: 120, width: 240, height: 80)
        let frame = WindowGeometry.resolve(size: WindowSize(width: 300, height: 100),
                                           position: nil,
                                           current: current,
                                           screen: screen)
        XCTAssertEqual(frame, WindowFrame(x: 100, y: 120, width: 300, height: 100))
    }

    func testPositionOnlyKeepsCurrentSize() {
        let current = WindowFrame(x: 100, y: 120, width: 240, height: 80)
        let frame = WindowGeometry.resolve(size: nil,
                                           position: .anchor(.bottomRight),
                                           current: current,
                                           screen: screen)
        XCTAssertEqual(frame, WindowFrame(x: 1000 - 240 - 24, y: 24, width: 240, height: 80))
    }

    func testAnchorCenters() {
        let current = WindowFrame(x: 0, y: 0, width: 200, height: 100)
        let frame = WindowGeometry.resolve(size: nil,
                                           position: .anchor(.center),
                                           current: current,
                                           screen: screen)
        XCTAssertEqual(frame, WindowFrame(x: 400, y: 350, width: 200, height: 100))
    }

    func testAbsolutePositionClampsIntoScreen() {
        let current = WindowFrame(x: 0, y: 0, width: 200, height: 100)
        let frame = WindowGeometry.resolve(size: nil,
                                           position: .absolute(x: 5000, y: -100),
                                           current: current,
                                           screen: screen)
        XCTAssertEqual(frame, WindowFrame(x: 800, y: 0, width: 200, height: 100))
    }

    func testMinimumSizeIsEnforced() {
        let current = WindowFrame(x: 50, y: 50, width: 200, height: 100)
        let frame = WindowGeometry.resolve(size: WindowSize(width: 10, height: 10),
                                           position: nil,
                                           current: current,
                                           screen: screen)
        XCTAssertEqual(frame.width, WindowSize.minimum.width)
        XCTAssertEqual(frame.height, WindowSize.minimum.height)
        XCTAssertEqual(frame.x, 50)
        XCTAssertEqual(frame.y, 50)
    }

    func testOverridesMergePerField() {
        let base = WindowSpec(size: WindowSize(width: 240, height: 80),
                              passthrough: false,
                              opacity: 0.5)
        let overrides = WindowSpec(position: .anchor(.topLeft), opacity: 0.8)
        let merged = base.merging(overrides: overrides)
        XCTAssertEqual(merged.size, base.size)
        XCTAssertEqual(merged.position, .anchor(.topLeft))
        XCTAssertEqual(merged.passthrough, false)
        XCTAssertEqual(merged.opacity, 0.8)
    }
}
