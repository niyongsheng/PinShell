import XCTest
@testable import PinShellCore

final class MCPClientConfigurationTests: XCTestCase {
    private var home: URL!
    private let context: (URL) -> MCPClientContext = { home in
        MCPClientContext(home: home, environment: [:], executableSearchPaths: [])
    }
    private let executable = URL(fileURLWithPath: "/Applications/PinShell.app/Contents/MacOS/PinShell")

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("PinShellMCPClientTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    // MARK: - Claude Code

    func testClaudeInstallCreatesConfig() throws {
        let ctx = context(home)
        let url = MCPClient.claudeCode.configURL(in: ctx)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))

        try MCPClient.claudeCode.install(executable: executable, in: ctx)

        let root = try jsonObject(at: url)
        let servers = try XCTUnwrap(root["mcpServers"] as? [String: Any])
        let entry = try XCTUnwrap(servers["pinshell"] as? [String: Any])
        XCTAssertEqual(entry["command"] as? String, executable.path)
        XCTAssertEqual(entry["args"] as? [String], ["mcp"])

        let status = MCPClient.claudeCode.status(executable: executable, in: ctx)
        XCTAssertTrue(status.detected)
        XCTAssertTrue(status.configured)
        XCTAssertTrue(status.commandMatches)
        XCTAssertFalse(status.needsUpdate)
    }

    func testClaudeInstallPreservesOtherConfiguration() throws {
        let ctx = context(home)
        let url = MCPClient.claudeCode.configURL(in: ctx)
        let existing: [String: Any] = [
            "numStartups": 120,
            "projects": ["/tmp/demo": ["history": ["hello"]]],
            "mcpServers": ["other": ["command": "/bin/echo", "args": ["hi"]]]
        ]
        try writeJSON(existing, to: url)

        try MCPClient.claudeCode.install(executable: executable, in: ctx)

        let root = try jsonObject(at: url)
        XCTAssertEqual(root["numStartups"] as? Int, 120)
        let projects = try XCTUnwrap(root["projects"] as? [String: Any])
        XCTAssertNotNil(projects["/tmp/demo"])
        let servers = try XCTUnwrap(root["mcpServers"] as? [String: Any])
        XCTAssertNotNil(servers["other"])
        XCTAssertNotNil(servers["pinshell"])
    }

    func testClaudeUninstallRemovesOnlyPinShell() throws {
        let ctx = context(home)
        let url = MCPClient.claudeCode.configURL(in: ctx)
        try MCPClient.claudeCode.install(executable: executable, in: ctx)
        var root = try jsonObject(at: url)
        var servers = try XCTUnwrap(root["mcpServers"] as? [String: Any])
        servers["other"] = ["command": "/bin/echo"]
        root["mcpServers"] = servers
        try writeJSON(root, to: url)

        try MCPClient.claudeCode.uninstall(in: ctx)

        let updated = try jsonObject(at: url)
        let updatedServers = try XCTUnwrap(updated["mcpServers"] as? [String: Any])
        XCTAssertNil(updatedServers["pinshell"])
        XCTAssertNotNil(updatedServers["other"])
    }

    func testSymlinkedConfigStaysLinked() throws {
        let ctx = context(home)
        let link = MCPClient.claudeCode.configURL(in: ctx)
        let target = home.appendingPathComponent("dotfiles-claude.json")
        try writeJSON(["mcpServers": [:]], to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        try MCPClient.claudeCode.install(executable: executable, in: ctx)

        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path),
                       target.path)
        let root = try jsonObject(at: target)
        let servers = try XCTUnwrap(root["mcpServers"] as? [String: Any])
        XCTAssertNotNil(servers["pinshell"])
    }

    func testInvalidJSONIsNotOverwritten() throws {
        let ctx = context(home)
        let url = MCPClient.claudeCode.configURL(in: ctx)
        try Data("not json".utf8).write(to: url)

        XCTAssertThrowsError(try MCPClient.claudeCode.install(executable: executable, in: ctx)) {
            XCTAssertEqual($0 as? MCPClientConfigError, .invalidJSON(url))
        }
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "not json")
    }

    func testStatusReportsStaleExecutable() throws {
        let ctx = context(home)
        let oldExecutable = URL(fileURLWithPath: "/tmp/old/PinShell")
        try MCPClient.claudeCode.install(executable: oldExecutable, in: ctx)

        let status = MCPClient.claudeCode.status(executable: executable, in: ctx)
        XCTAssertTrue(status.configured)
        XCTAssertFalse(status.commandMatches)
        XCTAssertTrue(status.needsUpdate)
    }

    // MARK: - Cursor / Pi

    func testCursorUsesMCPJSON() throws {
        let ctx = context(home)
        XCTAssertEqual(MCPClient.cursor.configURL(in: ctx).path,
                       home.appendingPathComponent(".cursor/mcp.json").path)

        try MCPClient.cursor.install(executable: executable, in: ctx)
        let root = try jsonObject(at: MCPClient.cursor.configURL(in: ctx))
        let servers = try XCTUnwrap(root["mcpServers"] as? [String: Any])
        XCTAssertNotNil(servers["pinshell"])
    }

    func testPiConfigPathHonorsEnvironment() throws {
        let ctx = MCPClientContext(home: home,
                                   environment: ["PI_CODING_AGENT_DIR": "~/custom-pi"],
                                   executableSearchPaths: [])
        XCTAssertEqual(MCPClient.pi.configURL(in: ctx).path,
                       home.appendingPathComponent("custom-pi/mcp.json").path)

        try MCPClient.pi.install(executable: executable, in: ctx)
        XCTAssertTrue(MCPClient.pi.isDetected(in: ctx))
        XCTAssertTrue(MCPClient.pi.status(executable: executable, in: ctx).configured)
    }

    func testPiDetectedByConfigDirectory() throws {
        let ctx = context(home)
        let directory = MCPClient.pi.configURL(in: ctx).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        XCTAssertTrue(MCPClient.pi.isDetected(in: ctx))
        XCTAssertFalse(MCPClient.pi.status(executable: executable, in: ctx).configured)
    }

    // MARK: - OpenCode

    func testOpenCodeUsesGlobalConfigPath() throws {
        let ctx = context(home)
        XCTAssertEqual(MCPClient.opencode.configURL(in: ctx).path,
                       home.appendingPathComponent(".config/opencode/opencode.json").path)

        try MCPClient.opencode.install(executable: executable, in: ctx)

        let root = try jsonObject(at: MCPClient.opencode.configURL(in: ctx))
        let mcp = try XCTUnwrap(root["mcp"] as? [String: Any])
        let servers = try XCTUnwrap(mcp["servers"] as? [String: Any])
        let entry = try XCTUnwrap(servers["pinshell"] as? [String: Any])
        XCTAssertEqual(entry["type"] as? String, "local")
        XCTAssertEqual(entry["command"] as? [String], [executable.path, "mcp"])

        let status = MCPClient.opencode.status(executable: executable, in: ctx)
        XCTAssertTrue(status.detected)
        XCTAssertTrue(status.configured)
        XCTAssertTrue(status.commandMatches)
        XCTAssertFalse(status.needsUpdate)
    }

    func testOpenCodeInstallPreservesOtherConfiguration() throws {
        let ctx = context(home)
        let url = MCPClient.opencode.configURL(in: ctx)
        let existing: [String: Any] = [
            "$schema": "https://opencode.ai/config.json",
            "theme": "system",
            "mcp": [
                "servers": [
                    "other": ["type": "local", "command": ["/bin/echo", "hi"]]
                ]
            ]
        ]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try writeJSON(existing, to: url)

        try MCPClient.opencode.install(executable: executable, in: ctx)

        let root = try jsonObject(at: url)
        XCTAssertEqual(root["$schema"] as? String, "https://opencode.ai/config.json")
        XCTAssertEqual(root["theme"] as? String, "system")
        let mcp = try XCTUnwrap(root["mcp"] as? [String: Any])
        let servers = try XCTUnwrap(mcp["servers"] as? [String: Any])
        XCTAssertNotNil(servers["other"])
        XCTAssertNotNil(servers["pinshell"])
    }

    func testOpenCodeUpdatesLegacyDirectEntryInPlace() throws {
        let ctx = context(home)
        let url = MCPClient.opencode.configURL(in: ctx)
        let existing: [String: Any] = [
            "mcp": [
                "pinshell": [
                    "type": "local",
                    "command": ["/old/PinShell", "mcp"]
                ]
            ]
        ]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try writeJSON(existing, to: url)

        try MCPClient.opencode.install(executable: executable, in: ctx)

        let root = try jsonObject(at: url)
        let mcp = try XCTUnwrap(root["mcp"] as? [String: Any])
        XCTAssertNil(mcp["servers"])
        let entry = try XCTUnwrap(mcp["pinshell"] as? [String: Any])
        XCTAssertEqual(entry["command"] as? [String], [executable.path, "mcp"])
        XCTAssertTrue(MCPClient.opencode.status(executable: executable, in: ctx).commandMatches)
    }

    func testOpenCodeUninstallRemovesOnlyPinShell() throws {
        let ctx = context(home)
        let url = MCPClient.opencode.configURL(in: ctx)
        try MCPClient.opencode.install(executable: executable, in: ctx)
        var root = try jsonObject(at: url)
        var mcp = try XCTUnwrap(root["mcp"] as? [String: Any])
        var servers = try XCTUnwrap(mcp["servers"] as? [String: Any])
        servers["other"] = ["type": "local", "command": ["/bin/echo", "hi"]]
        mcp["servers"] = servers
        root["mcp"] = mcp
        try writeJSON(root, to: url)

        try MCPClient.opencode.uninstall(in: ctx)

        let updated = try jsonObject(at: url)
        let updatedMcp = try XCTUnwrap(updated["mcp"] as? [String: Any])
        let updatedServers = try XCTUnwrap(updatedMcp["servers"] as? [String: Any])
        XCTAssertNil(updatedServers["pinshell"])
        XCTAssertNotNil(updatedServers["other"])
        XCTAssertFalse(MCPClient.opencode.status(executable: executable, in: ctx).configured)
    }

    func testOpenCodeConfigPathHonorsEnvironment() {
        let xdg = MCPClientContext(home: home,
                                   environment: ["XDG_CONFIG_HOME": "/tmp/opencode-config"],
                                   executableSearchPaths: [])
        XCTAssertEqual(MCPClient.opencode.configURL(in: xdg).path,
                       "/tmp/opencode-config/opencode/opencode.json")

        let custom = MCPClientContext(home: home,
                                      environment: ["OPENCODE_CONFIG": "/tmp/custom/opencode.json"],
                                      executableSearchPaths: [])
        XCTAssertEqual(MCPClient.opencode.configURL(in: custom).path,
                       "/tmp/custom/opencode.json")
    }

    func testOpenCodePrefersExistingJSONC() throws {
        let ctx = context(home)
        let directory = home.appendingPathComponent(".config/opencode")
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: true)
        let jsonc = directory.appendingPathComponent("opencode.jsonc")
        try Data("{\"mcp\": {}}".utf8).write(to: jsonc)

        XCTAssertEqual(MCPClient.opencode.configURL(in: ctx).path, jsonc.path)
    }

    func testOpenCodeStatusReportsStaleExecutable() throws {
        let ctx = context(home)
        let oldExecutable = URL(fileURLWithPath: "/tmp/old/PinShell")
        try MCPClient.opencode.install(executable: oldExecutable, in: ctx)

        let status = MCPClient.opencode.status(executable: executable, in: ctx)
        XCTAssertTrue(status.configured)
        XCTAssertFalse(status.commandMatches)
        XCTAssertTrue(status.needsUpdate)
    }

    // MARK: - Codex

    func testCodexInstallAppendsTOMLSection() throws {
        let ctx = context(home)
        let url = MCPClient.codex.configURL(in: ctx)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let existing = """
        model = "gpt-5"

        [mcp_servers.other]
        command = "/bin/echo"
        args = ["hi"]
        """
        try existing.write(to: url, atomically: true, encoding: .utf8)

        try MCPClient.codex.install(executable: executable, in: ctx)

        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("model = \"gpt-5\""))
        XCTAssertTrue(text.contains("[mcp_servers.other]"))
        XCTAssertTrue(text.contains("[mcp_servers.pinshell]"))
        XCTAssertTrue(text.contains("command = \"\(executable.path)\""))
        XCTAssertTrue(text.contains("args = [\"mcp\"]"))

        let status = MCPClient.codex.status(executable: executable, in: ctx)
        XCTAssertTrue(status.detected)
        XCTAssertTrue(status.configured)
        XCTAssertTrue(status.commandMatches)
    }

    func testCodexInstallReplacesExistingSectionAndSubtable() throws {
        let ctx = context(home)
        let url = MCPClient.codex.configURL(in: ctx)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let existing = """
        [mcp_servers.pinshell]
        command = "/old/PinShell"
        args = ["mcp"]

        [mcp_servers.pinshell.env]
        TOKEN = "x"

        [shell_environment_policy]
        inherit = "all"
        """
        try existing.write(to: url, atomically: true, encoding: .utf8)

        try MCPClient.codex.install(executable: executable, in: ctx)

        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(text.contains("/old/PinShell"))
        XCTAssertFalse(text.contains("TOKEN"))
        XCTAssertTrue(text.contains("[shell_environment_policy]"))
        XCTAssertEqual(text.components(separatedBy: "[mcp_servers.pinshell]").count - 1, 1)
        XCTAssertTrue(MCPClient.codex.status(executable: executable, in: ctx).commandMatches)
    }

    func testCodexUninstallRemovesSectionOnly() throws {
        let ctx = context(home)
        let url = MCPClient.codex.configURL(in: ctx)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let existing = """
        model = "gpt-5"

        [mcp_servers.other]
        command = "/bin/echo"
        """
        try existing.write(to: url, atomically: true, encoding: .utf8)
        try MCPClient.codex.install(executable: executable, in: ctx)

        try MCPClient.codex.uninstall(in: ctx)

        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(text.contains("[mcp_servers.pinshell]"))
        XCTAssertTrue(text.contains("[mcp_servers.other]"))
        XCTAssertTrue(text.contains("model = \"gpt-5\""))
        XCTAssertFalse(MCPClient.codex.status(executable: executable, in: ctx).configured)
    }

    func testCodexRefusesUnreadableConfig() throws {
        let ctx = context(home)
        let url = MCPClient.codex.configURL(in: ctx)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let original = Data([0xFF, 0xFE, 0x00, 0x01])
        try original.write(to: url)

        XCTAssertThrowsError(try MCPClient.codex.install(executable: executable, in: ctx)) {
            XCTAssertEqual($0 as? MCPClientConfigError, .unreadable(url))
        }
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testCodexConfigPathHonorsEnvironment() {
        let ctx = MCPClientContext(home: home,
                                   environment: ["CODEX_HOME": "/tmp/codex-home"],
                                   executableSearchPaths: [])
        XCTAssertEqual(MCPClient.codex.configURL(in: ctx).path,
                       "/tmp/codex-home/config.toml")
    }

    func testClaudeConfigPathHonorsEnvironment() {
        let ctx = MCPClientContext(home: home,
                                   environment: ["CLAUDE_CONFIG_DIR": "/tmp/claude-config"],
                                   executableSearchPaths: [])
        XCTAssertEqual(MCPClient.claudeCode.configURL(in: ctx).path,
                       "/tmp/claude-config/.claude.json")
    }

    // MARK: - TOML 辅助

    func testTableNameParsing() {
        XCTAssertEqual(MCPClient.tableName("[a.b]"), "a.b")
        XCTAssertEqual(MCPClient.tableName("  [[a.b]]  "), "a.b")
        XCTAssertEqual(MCPClient.tableName("[ mcp_servers.\"pinshell\" ]"), "mcp_servers.pinshell")
        XCTAssertEqual(MCPClient.tableName("[mcp_servers.pinshell] # local server"),
                       "mcp_servers.pinshell")
        XCTAssertNil(MCPClient.tableName("args = [\"mcp\"]"))
        XCTAssertNil(MCPClient.tableName("[\"a\", \"b\"]"))
        XCTAssertNil(MCPClient.tableName("[mcp_servers.pinshell] extra"))
    }

    // MARK: - 工具

    private func jsonObject(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func writeJSON(_ object: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted])
        try data.write(to: url)
    }
}
