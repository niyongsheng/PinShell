import Foundation
@testable import PinShellCore

enum TemplateLibraryFixtures {
    static let shaA = String(repeating: "a", count: 64)
    static let shaB = String(repeating: "b", count: 64)

    static func entry(id: String = "todo",
                      version: String = "1.0.0",
                      minAppVersion: String = "1.4.0",
                      sha256: String = shaA) -> TemplateLibraryEntry {
        TemplateLibraryEntry(
            id: id,
            version: version,
            file: "\(id).html",
            order: 3,
            minAppVersion: minAppVersion,
            category: "productivity",
            tags: ["tasks", "eisenhower"],
            defaultLanguage: "zh-Hans",
            fallbackLanguage: "en",
            languages: [
                "zh-Hans": TemplateLibraryLocalization(
                    name: "待办事项",
                    description: "支持列表与四象限两种视图的浮动待办清单"),
                "en": TemplateLibraryLocalization(
                    name: "Todo List",
                    description: "Floating todo list with list and Eisenhower views"),
            ],
            listing: [
                "zh-Hans": TemplateLibraryListing(
                    tagline: "把今天安放在屏幕一角。",
                    highlights: ["列表与四象限", "随手勾选"]),
                "en": TemplateLibraryListing(
                    tagline: "Keep today in the corner of your screen.",
                    highlights: ["List and Eisenhower views", "Quick capture"]),
            ],
            preview: TemplateLibraryPreview(
                mode: "live",
                url: "templates/\(id)/\(version)/\(id).html",
                width: 368,
                height: 480),
            payload: TemplateLibraryPayload(
                url: "templates/\(id)/\(version)/\(id).html",
                fileName: "\(id).html",
                bytes: 10,
                sha256: sha256,
                contentType: "text/html; charset=utf-8"),
            pages: [
                "zh-Hans": "templates/\(id)/",
                "en": "en/templates/\(id)/",
            ],
            changelog: [
                version: TemplateLibraryChangelogEntry(
                    date: "2026-11-23",
                    notes: [
                        "zh-Hans": "首个在线版本。",
                        "en": "First library release.",
                    ])
            ]
        )
    }

    static func index(entry: TemplateLibraryEntry? = nil) -> TemplateLibraryIndex {
        TemplateLibraryIndex(
            schemaVersion: 1,
            generatedAt: "2026-11-23T08:00:00Z",
            categories: [
                TemplateLibraryCategory(
                    id: "productivity",
                    names: ["zh-Hans": "效率", "en": "Productivity"])
            ],
            templates: [entry ?? self.entry()]
        )
    }

    static func indexData(entry: TemplateLibraryEntry? = nil) throws -> Data {
        try JSONEncoder().encode(index(entry: entry))
    }
}
