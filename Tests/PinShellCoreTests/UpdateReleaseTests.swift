import XCTest
@testable import PinShellCore

final class UpdateReleaseTests: XCTestCase {
    func testVersionCompare() {
        XCTAssertEqual(VersionNumber.compare("1.3.0", "1.2.9"), .orderedDescending)
        XCTAssertEqual(VersionNumber.compare("v1.3", "1.3.0"), .orderedSame)
        XCTAssertEqual(VersionNumber.compare("1.3.0-beta1", "1.3.0"), .orderedSame)
        XCTAssertEqual(VersionNumber.compare("2", "10"), .orderedAscending)
        XCTAssertEqual(VersionNumber.compare("V2.0.0", "1.99.99"), .orderedDescending)
    }

    func testDecodingReleaseWithAssets() throws {
        let json = """
        {
          "tag_name": "v1.4.0",
          "name": "v1.4.0",
          "body": "notes",
          "html_url": "https://example.com/releases/v1.4.0",
          "assets": [
            {"name": "PinShell-1.4.0.zip",
             "browser_download_url": "https://example.com/a.zip",
             "size": 10,
             "digest": "sha256:aaaaaaaa"},
            {"name": "PinShell-1.4.0-mac-universal.pkg",
             "browser_download_url": "https://example.com/a.pkg",
             "size": 20,
             "digest": "sha256:bbbbbbbb"}
          ]
        }
        """
        let release = try JSONDecoder().decode(UpdateRelease.self, from: Data(json.utf8))

        XCTAssertEqual(release.versionLabel, "1.4.0")
        XCTAssertEqual(release.assets.count, 2)
        XCTAssertEqual(release.pkgAsset?.name, "PinShell-1.4.0-mac-universal.pkg")
        XCTAssertEqual(release.pkgAsset?.size, 20)
        XCTAssertEqual(release.pkgAsset?.sha256, "bbbbbbbb")
    }

    func testStablePkgNameWins() throws {
        let json = """
        {
          "tag_name": "v1.4.0",
          "assets": [
            {"name": "PinShell-1.4.0-mac-universal.pkg",
             "browser_download_url": "https://example.com/versioned.pkg",
             "size": 20},
            {"name": "PinShell.pkg",
             "browser_download_url": "https://example.com/stable.pkg",
             "size": 20}
          ]
        }
        """
        let release = try JSONDecoder().decode(UpdateRelease.self, from: Data(json.utf8))
        XCTAssertEqual(release.pkgAsset?.name, "PinShell.pkg")
    }

    func testReleaseWithoutAssetsDecodes() throws {
        let release = try JSONDecoder().decode(UpdateRelease.self,
                                               from: Data(#"{"tag_name":"v1.0.0"}"#.utf8))
        XCTAssertTrue(release.assets.isEmpty)
        XCTAssertNil(release.pkgAsset)
        XCTAssertEqual(release.versionLabel, "1.0.0")
    }

    func testReleaseWithoutPkgFallsBackToNil() throws {
        let json = """
        {
          "tag_name": "v1.3.0",
          "assets": [
            {"name": "PinShell-1.3.0.dmg",
             "browser_download_url": "https://example.com/a.dmg",
             "size": 10}
          ]
        }
        """
        let release = try JSONDecoder().decode(UpdateRelease.self, from: Data(json.utf8))
        XCTAssertNil(release.pkgAsset)
    }

    func testAssetDigestParsing() {
        let url = URL(string: "https://example.com/a.pkg")!
        XCTAssertEqual(ReleaseAsset(name: "a", browserDownloadURL: url, size: 1,
                                    digest: "SHA256:ABCD").sha256, "abcd")
        XCTAssertNil(ReleaseAsset(name: "a", browserDownloadURL: url, size: 1,
                                  digest: "sha512:abcd").sha256)
        XCTAssertNil(ReleaseAsset(name: "a", browserDownloadURL: url, size: 1,
                                  digest: nil).sha256)
    }
}
