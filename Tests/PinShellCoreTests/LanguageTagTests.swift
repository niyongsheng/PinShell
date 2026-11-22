import XCTest
@testable import PinShellCore

final class LanguageTagTests: XCTestCase {
    func testNormalize() {
        XCTAssertEqual(LanguageTag.normalize(" EN_us "), "en-us")
        XCTAssertEqual(LanguageTag.normalize("zh-Hans-CN"), "zh-hans-cn")
        XCTAssertEqual(LanguageTag.normalize(""), "")
    }

    func testMatchesByPrimaryLanguage() {
        XCTAssertTrue(LanguageTag.matches("en", "en-US"))
        XCTAssertTrue(LanguageTag.matches("zh-Hans", "zh-CN"))
        XCTAssertFalse(LanguageTag.matches("zh-Hans", "zh-Hant"))
        XCTAssertFalse(LanguageTag.matches("en", "fr"))
        XCTAssertFalse(LanguageTag.matches("", "en"))
    }

    func testBestMatch() {
        let available = ["zh-Hans", "en"]
        XCTAssertEqual(LanguageTag.bestMatch(available: available, preferred: ["en-US"]), "en")
        XCTAssertEqual(LanguageTag.bestMatch(available: available, preferred: ["zh-CN"]), "zh-Hans")
        XCTAssertNil(LanguageTag.bestMatch(available: available, preferred: ["fr"]))
    }

    func testScriptAwareChineseMatching() {
        let available = ["zh-Hans", "zh-Hant", "en"]
        XCTAssertEqual(LanguageTag.bestMatch(available: available, preferred: ["zh-TW"]), "zh-Hant")
        XCTAssertEqual(LanguageTag.bestMatch(available: available, preferred: ["zh-CN"]), "zh-Hans")
        XCTAssertEqual(LanguageTag.bestMatch(available: available, preferred: ["zh-HK"]), "zh-Hant")
    }

    func testTemplatePreferredLanguagesAreSystemFirst() {
        // 该值随运行环境变化，只校验系统语言在前、应用语言作为补充。
        let tags = LanguageTag.templatePreferredLanguages
        XCTAssertFalse(tags.isEmpty)
        XCTAssertEqual(LanguageTag.unique(tags).count, tags.count)
    }

    func testUniquePreservesOrder() {
        XCTAssertEqual(LanguageTag.unique(["en-US", "en-us", "zh-Hans", "", "en"]),
                       ["en-US", "zh-Hans", "en"])
    }
}
