import XCTest
@testable import PinShellCore

final class MCPPromptTests: XCTestCase {
    func testDefinitionsUseUniqueNames() {
        let names = MCPPromptCatalog.definitions.map(\.name)
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertFalse(names.contains { $0.isEmpty || $0.contains("/") || $0.contains(" ") })
    }

    func testEveryDefinitionRendersWithRequiredArguments() throws {
        for definition in MCPPromptCatalog.definitions {
            let arguments = Dictionary(uniqueKeysWithValues:
                definition.arguments.map { ($0.name, "sample") })
            let rendered = try MCPPromptCatalog.render(name: definition.name,
                                                       arguments: arguments)
            XCTAssertFalse(rendered.text.isEmpty, definition.name)
            XCTAssertFalse(rendered.description.isEmpty, definition.name)
        }
    }

    func testRequiredArgumentsAreEnforced() {
        for definition in MCPPromptCatalog.definitions {
            guard let first = definition.arguments.first(where: \.required) else { continue }
            var arguments = Dictionary(uniqueKeysWithValues:
                definition.arguments.map { ($0.name, "sample") })
            arguments[first.name] = "   "

            XCTAssertThrowsError(try MCPPromptCatalog.render(name: definition.name,
                                                             arguments: arguments)) { error in
                XCTAssertEqual(error as? MCPPromptError,
                               .missingArgument(prompt: definition.name,
                                                argument: first.name))
            }
        }
    }

    func testUnknownPromptThrows() {
        XCTAssertThrowsError(try MCPPromptCatalog.render(name: "nope", arguments: [:])) {
            XCTAssertEqual($0 as? MCPPromptError, .unknownPrompt("nope"))
        }
    }

    func testCreatePanelEmbedsTaskAndHints() throws {
        let rendered = try MCPPromptCatalog.render(name: "create-panel", arguments: [
            "task": "Show today's build status",
            "size": "320x120",
            "position": "bottom-right"
        ])

        XCTAssertTrue(rendered.text.contains("Show today's build status"))
        XCTAssertTrue(rendered.text.contains("size 320x120"))
        XCTAssertTrue(rendered.text.contains("position bottom-right"))
        XCTAssertTrue(rendered.text.contains("pinshell_html"))
        XCTAssertTrue(rendered.text.contains("pinshell_poll_events"))
    }

    func testCreatePanelFallsBackForInvalidHints() throws {
        let rendered = try MCPPromptCatalog.render(name: "create-panel", arguments: [
            "task": "x",
            "size": "huge",
            "position": "nowhere"
        ])

        XCTAssertTrue(rendered.text.contains("size 320x200"))
        XCTAssertTrue(rendered.text.contains("position top-right"))
    }

    func testLiveMonitorClampsInterval() throws {
        let rendered = try MCPPromptCatalog.render(name: "live-monitor", arguments: [
            "task": "CPU load",
            "interval": "1"
        ])

        XCTAssertTrue(rendered.text.contains("Refresh interval: 15 seconds"))
        XCTAssertTrue(rendered.text.contains("setInterval(refresh, 15000)"))
    }

    func testAuthoringGuideNeedsNoArguments() throws {
        let rendered = try MCPPromptCatalog.render(name: "authoring-guide", arguments: [:])
        XCTAssertTrue(rendered.text.contains("window.pinshell"))
        XCTAssertTrue(rendered.text.contains("pinshell:size"))
    }

    func testPromptsUseSystemLanguageAndAllowRichMedia() throws {
        let rendered = try MCPPromptCatalog.render(name: "authoring-guide", arguments: [:])
        XCTAssertTrue(rendered.text.contains(MCPPromptCatalog.userLanguageName))
        XCTAssertTrue(rendered.text.contains("operating system language"))
        XCTAssertTrue(rendered.text.contains("Use PinShell proactively"))
        XCTAssertTrue(rendered.text.contains("<audio>/<video>"))
        XCTAssertTrue(rendered.text.contains("CSS/SVG/Canvas animation"))
    }

    func testLanguageNameFallsBackToGenericWording() {
        XCTAssertEqual(MCPPromptCatalog.languageName(for: nil), "the user's language")
        XCTAssertEqual(MCPPromptCatalog.languageName(for: ""), "the user's language")
        XCTAssertTrue(MCPPromptCatalog.languageName(for: "zh-Hans-CN").contains("Chinese"))
        XCTAssertTrue(MCPPromptCatalog.languageName(for: "en-US").contains("English"))
    }
}
