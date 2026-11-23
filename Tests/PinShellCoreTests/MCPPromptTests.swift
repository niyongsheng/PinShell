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

    func testPetCompanionPromptDocumentsProtocol() throws {
        let rendered = try MCPPromptCatalog.render(name: "pet-companion", arguments: [
            "task": "Fix the failing build"
        ])

        XCTAssertTrue(rendered.text.contains("Fix the failing build"))
        XCTAssertTrue(rendered.text.contains("desktop-pet.html"))
        XCTAssertTrue(rendered.text.contains("pet:hello"))
        XCTAssertTrue(rendered.text.contains("pet:task"))
        XCTAssertTrue(rendered.text.contains("pet:ask"))
        XCTAssertTrue(rendered.text.contains("pet:reply"))
        XCTAssertTrue(rendered.text.contains("pinshell_poll_events"))
    }

    func testPetCompanionWithoutTaskUsesDefault() throws {
        let rendered = try MCPPromptCatalog.render(name: "pet-companion", arguments: [:])
        XCTAssertTrue(rendered.text.contains("keep the user company"))
        XCTAssertTrue(rendered.text.contains("pet:reset"))
    }

    func testPetCompanionRequiresOnlineLibraryInstall() throws {
        let rendered = try MCPPromptCatalog.render(name: "pet-companion", arguments: [:])
        XCTAssertTrue(rendered.text.contains("Online Template Library"))
        XCTAssertTrue(rendered.text.contains("desktop-pet.html"))
        XCTAssertTrue(rendered.text.contains("Do not"))
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

    func testAuthoringGuideDocumentsCurrentAssetAndLocalizationContract() throws {
        let rendered = try MCPPromptCatalog.render(name: "authoring-guide", arguments: [:])

        XCTAssertTrue(rendered.text.contains("agent folder"))
        XCTAssertTrue(rendered.text.contains("design-tokens.css"))
        XCTAssertTrue(rendered.text.contains("pinshell-i18n.js"))
        XCTAssertTrue(rendered.text.contains("window.pinshell.language"))
        XCTAssertTrue(rendered.text.contains("pinshell:order"))
        XCTAssertTrue(rendered.text.contains("data-i18n"))
        XCTAssertFalse(rendered.text.contains("512 KB"))
    }

    func testCreatePanelPrefersBundledTemplates() throws {
        let rendered = try MCPPromptCatalog.render(name: "create-panel", arguments: [
            "task": "Show CPU and memory"
        ])

        XCTAssertTrue(rendered.text.contains("pinshell_templates"))
        XCTAssertTrue(rendered.text.contains("pinshell_template_show"))
        XCTAssertTrue(rendered.text.contains("system-monitor"))
        XCTAssertTrue(rendered.text.contains("pinshell_close"))
    }

    func testInteractivePanelDocumentsCancellationAndAcknowledgement() throws {
        let rendered = try MCPPromptCatalog.render(name: "interactive-panel", arguments: [
            "task": "Pick a deployment window"
        ])

        XCTAssertTrue(rendered.text.contains("ui:ready"))
        XCTAssertTrue(rendered.text.contains("ui:submit"))
        XCTAssertTrue(rendered.text.contains("ui:cancel"))
        XCTAssertTrue(rendered.text.contains("pinshell_await_event"))
        XCTAssertTrue(rendered.text.contains("pinshell_state"))
        XCTAssertTrue(rendered.text.contains("agent:message"))
        XCTAssertTrue(rendered.text.contains("pinshell_close"))
    }

    func testAuthoringGuideDocumentsEventEnvelopeAndState() throws {
        let rendered = try MCPPromptCatalog.render(name: "authoring-guide", arguments: [:])

        XCTAssertTrue(rendered.text.contains("setState(state)"))
        XCTAssertTrue(rendered.text.contains("patchState"))
        XCTAssertTrue(rendered.text.contains("state:delta"))
        XCTAssertTrue(rendered.text.contains("pinshell_await_event"))
        XCTAssertTrue(rendered.text.contains("seq"))
        XCTAssertTrue(rendered.text.contains("type"))
    }

    func testLiveMonitorReferencesLiveTemplatesAndFetchLimits() throws {
        let rendered = try MCPPromptCatalog.render(name: "live-monitor", arguments: [
            "task": "Deploy status",
            "source": "https://example.com/status.json"
        ])

        XCTAssertTrue(rendered.text.contains("system-monitor.html"))
        XCTAssertTrue(rendered.text.contains("system:stats"))
        XCTAssertTrue(rendered.text.contains("goal-progress.html"))
        XCTAssertTrue(rendered.text.contains("pinshell.fetch"))
        XCTAssertTrue(rendered.text.contains("2 MB"))
        XCTAssertTrue(rendered.text.contains("document.hidden"))
    }

    func testEditTemplatePreservesLocalizationAndProtocols() throws {
        let rendered = try MCPPromptCatalog.render(name: "edit-template", arguments: [
            "name": "system-monitor.html",
            "changes": "Add a network sparkline"
        ])

        XCTAssertTrue(rendered.text.contains("pinshell:title"))
        XCTAssertTrue(rendered.text.contains("pinshell:order"))
        XCTAssertTrue(rendered.text.contains("PINSHELL_STRINGS"))
        XCTAssertTrue(rendered.text.contains("AGENT PROTOCOL"))
        XCTAssertTrue(rendered.text.contains("512 KB"))
    }

    func testPetCompanionDocumentsV2Protocol() throws {
        let rendered = try MCPPromptCatalog.render(name: "pet-companion", arguments: [:])

        XCTAssertTrue(rendered.text.contains("pet:ready"))
        XCTAssertTrue(rendered.text.contains("agent:message"))
        XCTAssertTrue(rendered.text.contains("window.PinShellPet"))
        XCTAssertTrue(rendered.text.contains("within ~10 seconds"))
    }

    func testLanguageNameFallsBackToGenericWording() {
        XCTAssertEqual(MCPPromptCatalog.languageName(for: nil), "the user's language")
        XCTAssertEqual(MCPPromptCatalog.languageName(for: ""), "the user's language")
        XCTAssertTrue(MCPPromptCatalog.languageName(for: "zh-Hans-CN").contains("Chinese"))
        XCTAssertTrue(MCPPromptCatalog.languageName(for: "en-US").contains("English"))
    }
}
