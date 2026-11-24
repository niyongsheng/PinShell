import XCTest
@testable import PinShellCore

final class DisplayModeTests: XCTestCase {
    func testPersistedRawValuesAreStable() {
        XCTAssertEqual(DisplayMode.desktop.rawValue, "desktop")
        XCTAssertEqual(DisplayMode.menuBar.rawValue, "menuBar")
    }

    func testRoundTripsKnownValues() {
        for mode in DisplayMode.allCases {
            XCTAssertEqual(DisplayMode(rawValue: mode.rawValue), mode)
        }
    }

    func testRejectsUnknownValue() {
        XCTAssertNil(DisplayMode(rawValue: "popover"))
        XCTAssertNil(DisplayMode(rawValue: ""))
    }
}
