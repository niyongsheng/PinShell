import XCTest
@testable import PinShellCore

/// 校验内置模板的 i18n block 完整：默认语言存在、各语言有 meta、
/// 非默认语言覆盖 HTML/JS 里引用的全部 key。
final class TemplateI18nCoverageTests: XCTestCase {
    private var templatesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // PinShellCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Resources/templates")
    }

    func testBuiltinTemplatesDeclareCompleteI18nBlocks() throws {
        let files = try FileManager.default.contentsOfDirectory(
            at: templatesDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension.lowercased() == "html" }.sorted { $0.path < $1.path }
        XCTAssertFalse(files.isEmpty)

        for file in files {
            let html = try String(contentsOf: file, encoding: .utf8)
            let block = try XCTUnwrap(TemplateI18n.extractBlock(from: html),
                                      "\(file.lastPathComponent): missing i18n block")
            let json = try XCTUnwrap(block.json,
                                     "\(file.lastPathComponent): invalid i18n JSON")
            let defaultLanguage = try XCTUnwrap(json["default"] as? String,
                                                "\(file.lastPathComponent): missing default")
            let languages = try XCTUnwrap(json["languages"] as? [String: Any],
                                          "\(file.lastPathComponent): missing languages")
            XCTAssertTrue(languages.keys.contains(where: { LanguageTag.matches($0, defaultLanguage) }),
                          "\(file.lastPathComponent): default \(defaultLanguage) not declared")
            if let fallback = json["fallback"] as? String {
                XCTAssertTrue(languages.keys.contains(where: { LanguageTag.matches($0, fallback) }),
                              "\(file.lastPathComponent): fallback \(fallback) not declared")
            }

            for (tag, rawEntry) in languages {
                let entry = try XCTUnwrap(rawEntry as? [String: Any],
                                          "\(file.lastPathComponent)/\(tag): invalid entry")
                let meta = try XCTUnwrap(entry["meta"] as? [String: Any],
                                         "\(file.lastPathComponent)/\(tag): missing meta")
                XCTAssertFalse((meta["name"] as? String ?? "").isEmpty,
                               "\(file.lastPathComponent)/\(tag): empty name")
                XCTAssertFalse((meta["description"] as? String ?? "").isEmpty,
                               "\(file.lastPathComponent)/\(tag): empty description")
            }

            let requiredKeys = Self.referencedKeys(in: html)
            for (tag, rawEntry) in languages
                where !LanguageTag.matches(tag, defaultLanguage) {
                let entry = rawEntry as? [String: Any] ?? [:]
                let ui = entry["ui"] as? [String: Any] ?? [:]
                let missing = requiredKeys.subtracting(ui.keys)
                XCTAssertTrue(missing.isEmpty,
                              "\(file.lastPathComponent)/\(tag): missing keys \(missing.sorted())")
            }
        }
    }

    func testBuiltinTemplatesResolveEnglishAndChineseMetadata() throws {
        let files = try FileManager.default.contentsOfDirectory(
            at: templatesDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension.lowercased() == "html" }.sorted { $0.path < $1.path }

        for file in files {
            let html = try String(contentsOf: file, encoding: .utf8)
            let en = HTMLTemplateMetadata.parse(html: html, preferredLanguages: ["en-US"])
            XCTAssertEqual(en.resolvedLanguage, "en", file.lastPathComponent)
            XCTAssertFalse((en.title ?? "").isEmpty, file.lastPathComponent)

            let zh = HTMLTemplateMetadata.parse(html: html, preferredLanguages: ["zh-Hans-CN"])
            XCTAssertEqual(zh.resolvedLanguage, "zh-Hans", file.lastPathComponent)
            XCTAssertFalse((zh.title ?? "").isEmpty, file.lastPathComponent)
        }
    }

    private static func referencedKeys(in html: String) -> Set<String> {
        var keys = Set<String>()
        let patterns = [
            #"<[^>]+\bdata-i18n\s*=\s*"([^"]+)""#,
            #"<[^>]+\bdata-i18n-[a-z-]+\s*=\s*"([^"]+)""#,
            #"PS\.t\(\s*['"]([^'"]+)['"]"#,
            #"PS\.list\(\s*['"]([^'"]+)['"]"#,
            #"PS\.get\(\s*['"]([^'"]+)['"]"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let ns = html as NSString
            for match in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
                guard match.numberOfRanges > 1 else { continue }
                keys.insert(ns.substring(with: match.range(at: 1)))
            }
        }
        return keys
    }
}
