import XCTest
@testable import PinShellCore

final class MenuBarPopoverGeometryTests: XCTestCase {
    private let screen = WindowFrame(x: 0, y: 0, width: 1000, height: 800)

    func testCentersBelowIcon() {
        let icon = WindowFrame(x: 400, y: 700, width: 24, height: 22)
        let frame = MenuBarPopoverGeometry.resolve(
            size: WindowSize(width: 240, height: 80),
            iconFrame: icon,
            visibleFrame: screen
        )
        XCTAssertEqual(frame, WindowFrame(x: 292, y: 614, width: 240, height: 80))
        XCTAssertEqual(frame.maxY, icon.minY - MenuBarPopoverGeometry.defaultGap)
    }

    func testKeepsPanelBelowMenuBar() {
        let visible = WindowFrame(x: 0, y: 0, width: 1000, height: 777)
        let icon = WindowFrame(x: 488, y: 778, width: 24, height: 22)
        let frame = MenuBarPopoverGeometry.resolve(
            size: WindowSize(width: 240, height: 80),
            iconFrame: icon,
            visibleFrame: visible
        )
        XCTAssertEqual(frame, WindowFrame(x: 380, y: 691, width: 240, height: 80))
    }

    func testClampsToRightEdge() {
        let icon = WindowFrame(x: 980, y: 700, width: 24, height: 22)
        let frame = MenuBarPopoverGeometry.resolve(
            size: WindowSize(width: 400, height: 80),
            iconFrame: icon,
            visibleFrame: screen
        )
        XCTAssertEqual(frame, WindowFrame(x: 592, y: 614, width: 400, height: 80))
    }

    func testClampsToLeftEdge() {
        let icon = WindowFrame(x: 0, y: 700, width: 24, height: 22)
        let frame = MenuBarPopoverGeometry.resolve(
            size: WindowSize(width: 240, height: 80),
            iconFrame: icon,
            visibleFrame: screen
        )
        XCTAssertEqual(frame, WindowFrame(x: 8, y: 614, width: 240, height: 80))
    }

    func testClampsTallPanelToAvailableHeight() {
        let visible = WindowFrame(x: 0, y: 0, width: 1000, height: 777)
        let icon = WindowFrame(x: 488, y: 778, width: 24, height: 22)
        let frame = MenuBarPopoverGeometry.resolve(
            size: WindowSize(width: 240, height: 1000),
            iconFrame: icon,
            visibleFrame: visible
        )
        XCTAssertEqual(frame, WindowFrame(x: 380, y: 8, width: 240, height: 763))
    }

    func testClampsWidePanelToScreenWidth() {
        let icon = WindowFrame(x: 400, y: 700, width: 24, height: 22)
        let frame = MenuBarPopoverGeometry.resolve(
            size: WindowSize(width: 5000, height: 80),
            iconFrame: icon,
            visibleFrame: screen
        )
        XCTAssertEqual(frame, WindowFrame(x: 8, y: 614, width: 984, height: 80))
    }

    func testEnforcesMinimumSize() {
        let icon = WindowFrame(x: 400, y: 700, width: 24, height: 22)
        let frame = MenuBarPopoverGeometry.resolve(
            size: WindowSize(width: 10, height: 10),
            iconFrame: icon,
            visibleFrame: screen
        )
        XCTAssertEqual(frame, WindowFrame(x: 372, y: 654, width: 80, height: 40))
    }

    func testNilIconFallsBackToTopCenter() {
        let frame = MenuBarPopoverGeometry.resolve(
            size: WindowSize(width: 240, height: 80),
            iconFrame: nil,
            visibleFrame: screen
        )
        XCTAssertEqual(frame, WindowFrame(x: 380, y: 714, width: 240, height: 80))
    }

    func testSupportsSecondaryDisplayOrigin() {
        let visible = WindowFrame(x: 1440, y: 0, width: 1920, height: 1055)
        let icon = WindowFrame(x: 2400, y: 1056, width: 24, height: 22)
        let frame = MenuBarPopoverGeometry.resolve(
            size: WindowSize(width: 320, height: 160),
            iconFrame: icon,
            visibleFrame: visible
        )
        XCTAssertEqual(frame, WindowFrame(x: 2252, y: 889, width: 320, height: 160))
    }

    func testSupportsNegativeOriginDisplay() {
        let visible = WindowFrame(x: -1920, y: -200, width: 1920, height: 1080)
        let icon = WindowFrame(x: -960, y: 881, width: 24, height: 22)
        let frame = MenuBarPopoverGeometry.resolve(
            size: WindowSize(width: 240, height: 80),
            iconFrame: icon,
            visibleFrame: visible
        )
        XCTAssertEqual(frame, WindowFrame(x: -1068, y: 794, width: 240, height: 80))
    }

    func testHonorsCustomGapAndInset() {
        let icon = WindowFrame(x: 400, y: 700, width: 24, height: 22)
        let frame = MenuBarPopoverGeometry.resolve(
            size: WindowSize(width: 240, height: 80),
            iconFrame: icon,
            visibleFrame: screen,
            gap: 0,
            inset: 0
        )
        XCTAssertEqual(frame, WindowFrame(x: 292, y: 620, width: 240, height: 80))
    }

    func testSanitizesNonFiniteSize() {
        let icon = WindowFrame(x: 400, y: 700, width: 24, height: 22)
        let frame = MenuBarPopoverGeometry.resolve(
            size: WindowSize(width: .nan, height: -10),
            iconFrame: icon,
            visibleFrame: screen
        )
        XCTAssertEqual(frame, WindowFrame(x: 372, y: 654, width: 80, height: 40))
    }

    func testPanelNeverStartsAboveVisibleTop() {
        let visible = WindowFrame(x: 0, y: 0, width: 1000, height: 777)
        let icon = WindowFrame(x: 488, y: 778, width: 24, height: 22)
        let frame = MenuBarPopoverGeometry.resolve(
            size: WindowSize(width: 240, height: 5000),
            iconFrame: icon,
            visibleFrame: visible
        )
        XCTAssertLessThanOrEqual(frame.maxY, visible.maxY)
        XCTAssertGreaterThanOrEqual(frame.minY, visible.minY)
        XCTAssertEqual(frame.maxY, visible.maxY - MenuBarPopoverGeometry.defaultGap)
    }
}
