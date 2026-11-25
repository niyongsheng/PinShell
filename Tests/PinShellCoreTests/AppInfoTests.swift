import XCTest
@testable import PinShellCore

final class AppInfoTests: XCTestCase {
    func testAppInfoMatchesInfoPlist() throws {
        let plistURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/Info.plist")
        let data = try Data(contentsOf: plistURL)
        let plist = try PropertyListSerialization.propertyList(
            from: data, options: [], format: nil) as? [String: Any]

        XCTAssertEqual(plist?["CFBundleIdentifier"] as? String,
                       PinShellAppInfo.bundleIdentifier)
        XCTAssertEqual(plist?["CFBundleName"] as? String,
                       PinShellAppInfo.name)
        XCTAssertEqual(plist?["CFBundleExecutable"] as? String,
                       PinShellAppInfo.name)
    }
}
