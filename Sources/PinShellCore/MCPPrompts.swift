import Foundation

// MARK: - 定义

/// MCP prompt 的参数声明（对应 `prompts/list` 的 `arguments`）。
public struct MCPPromptArgument: Equatable, Sendable {
    public let name: String
    public let description: String
    public let required: Bool

    public init(name: String, description: String, required: Bool = true) {
        self.name = name
        self.description = description
        self.required = required
    }
}

/// `prompts/list` 返回的 prompt 描述。
public struct MCPPromptDefinition: Equatable, Sendable {
    public let name: String
    public let title: String
    public let description: String
    public let arguments: [MCPPromptArgument]

    public init(name: String,
                title: String,
                description: String,
                arguments: [MCPPromptArgument]) {
        self.name = name
        self.title = title
        self.description = description
        self.arguments = arguments
    }
}

/// `prompts/get` 的渲染结果。
public struct RenderedMCPPrompt: Equatable, Sendable {
    public let description: String
    public let text: String

    public init(description: String, text: String) {
        self.description = description
        self.text = text
    }
}

public enum MCPPromptError: Error, LocalizedError, Equatable {
    case unknownPrompt(String)
    case missingArgument(prompt: String, argument: String)

    public var errorDescription: String? {
        switch self {
        case .unknownPrompt(let name):
            return "Unknown prompt: \(name)"
        case .missingArgument(let prompt, let argument):
            return "Prompt \(prompt) requires argument: \(argument)"
        }
    }
}

// MARK: - 目录

/// PinShell 的 MCP prompts。
///
/// Prompt 由用户在客户端选择（Claude Code 中表现为 slash command），渲染成一条
/// user message，用来把 PinShell 的 HTML 契约和固定工作流交给 agent。
public enum MCPPromptCatalog {
    /// 用户的操作系统语言（用户能听懂的语言），用于约定 agent 的交互语言。
    public static var userLanguageName: String {
        languageName(for: Locale.preferredLanguages.first)
    }

    /// 与用户交互的共同约定：语言、主动性与媒体。所有 prompt 共用，避免各处描述漂移。
    public static var interactionGuide: String {
        """
        User interaction:
        - Reply to the user in \(userLanguageName), the operating system language, and write every panel label, message, and error in it. Switch when the user writes in another language or asks.
        - Use PinShell proactively when a visual, interactive, or live response is clearer than text (progress, status, choices, confirmations, alerts); show the panel without asking first. Keep it small, dismiss it when done, and never duplicate chat text.
        - Rich media is welcome: inline SVG or https images, CSS/SVG/Canvas animation, emoji, short <audio>/<video> clips, and synthesized sound. Keep it light; make sound brief, quiet, and non-repeating; never block first paint.
        """
    }

    /// HTML 作者契约；所有面板类 prompt 共用，避免各处描述漂移。
    public static var authoringGuide: String {
    """
    PinShell shows local HTML in a transparent, always-on-top macOS overlay. \
    The page has no browser chrome and lives at a fixed window size.

    Window metadata (put in <head>):
      <title>Panel title</title>
      <meta name="description" content="What this panel shows">
      <meta name="pinshell:size" content="320x120">
      <meta name="pinshell:position" content="bottom-right">
      <meta name="pinshell:passthrough" content="false">
      <meta name="pinshell:opacity" content="0.92">
      <meta name="pinshell:radius" content="18">
    Position accepts top-left|top|top-right|left|center|right|bottom-left|bottom|bottom-right, or "x,y".

    Base CSS:
      html, body { margin: 0; width: 100%; height: 100%; background: transparent; overflow: hidden; }
      body { font: 13px -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif; color: #fff; user-select: none; }
    Floating content needs its own background, padding, and rounded corners; the window itself is transparent.

    JS bridge (window.pinshell):
      setSize(w, h) / setPosition('bottom-right' | x, y) / setPassthrough(bool) / setOpacity(0..1) / setRadius(px)
      emit(name, data)             page -> agent, read with pinshell_poll_events
      on(name, callback)           agent -> page, sent with pinshell_emit; callback receives data
      log(...)                     forwarded to the agent as a log event
      await fetch(url, {headers})  https only, GET, 15 s timeout, 2 MB cap

    Delivery rules:
    - pinshell_html writes a complete document, shows it, and waits for load by default.
    - pinshell_eval updates the live DOM; prefer it over reloading for small updates.
    - pinshell_emit dispatches events into the page; pinshell_poll_events long-polls up to 10 s for page events.
    - Keep the panel compact and readable at its declared size, avoid layout shift, and respect prefers-reduced-motion.

    \(interactionGuide)
    """
    }

    /// MCP `initialize` 的 server instructions（服务端与控制台展示共用）。
    public static var serverInstructions: String {
        """
        PinShell is an always-on-top HTML overlay on macOS. \
        Be proactive: when a visual, interactive, or live response is clearer than chat — \
        progress, status, comparisons, choices, confirmations, alerts — show a compact panel \
        without asking first; prefer buttons + pinshell_poll_events over typed questions. \
        Keep panels small, close them when done, and never repeat what chat already says. \
        pinshell_html renders HTML; pinshell_eval updates the live DOM; \
        pinshell_emit and pinshell_poll_events exchange events. \
        Window hints: <meta name="pinshell:size|position|passthrough|opacity|radius">. \
        window.pinshell: setSize, setPosition, setPassthrough, setOpacity, setRadius, \
        emit, on, log, and an https-only fetch. \
        Reply in \(userLanguageName) (the OS language) and write on-screen \
        copy in it; panels may use images, animation, sound, and video.
        """
    }

    public static let definitions: [MCPPromptDefinition] = [
        MCPPromptDefinition(
            name: "create-panel",
            title: "Create a panel",
            description: "Author a complete PinShell overlay panel and display it.",
            arguments: [
                MCPPromptArgument(name: "task",
                                  description: "What the panel should show or do."),
                MCPPromptArgument(name: "size",
                                  description: "Window size such as 320x120.",
                                  required: false),
                MCPPromptArgument(name: "position",
                                  description: "Anchor such as bottom-right, or x,y.",
                                  required: false)
            ]
        ),
        MCPPromptDefinition(
            name: "interactive-panel",
            title: "Create an interactive panel",
            description: "Collect a user decision or input and report it back through events.",
            arguments: [
                MCPPromptArgument(name: "task",
                                  description: "The question or input the panel should collect."),
                MCPPromptArgument(name: "options",
                                  description: "Comma-separated choices to offer.",
                                  required: false)
            ]
        ),
        MCPPromptDefinition(
            name: "live-monitor",
            title: "Create a live monitor",
            description: "Build a panel that refreshes from an https endpoint or agent-pushed updates.",
            arguments: [
                MCPPromptArgument(name: "task",
                                  description: "What metric or state the panel should display."),
                MCPPromptArgument(name: "source",
                                  description: "https URL to poll, or a description of the agent-supplied data.",
                                  required: false),
                MCPPromptArgument(name: "interval",
                                  description: "Refresh interval in seconds (15-3600, default 60).",
                                  required: false)
            ]
        ),
        MCPPromptDefinition(
            name: "edit-template",
            title: "Edit a template",
            description: "Read, modify, and write a PinShell template while preserving its metadata.",
            arguments: [
                MCPPromptArgument(name: "name",
                                  description: "Template file name, e.g. todo.html."),
                MCPPromptArgument(name: "changes",
                                  description: "What to change in the template.")
            ]
        ),
        MCPPromptDefinition(
            name: "authoring-guide",
            title: "HTML authoring guide",
            description: "The full PinShell HTML, window metadata, JS bridge, and user-interaction contract.",
            arguments: []
        )
    ]

    public static var names: [String] { definitions.map(\.name) }

    public static func render(name: String,
                              arguments: [String: String]) throws -> RenderedMCPPrompt {
        guard let definition = definitions.first(where: { $0.name == name }) else {
            throw MCPPromptError.unknownPrompt(name)
        }

        let text: String
        switch name {
        case "create-panel":
            text = try createPanel(arguments)
        case "interactive-panel":
            text = try interactivePanel(arguments)
        case "live-monitor":
            text = try liveMonitor(arguments)
        case "edit-template":
            text = try editTemplate(arguments)
        case "authoring-guide":
            text = authoringGuidePrompt()
        default:
            throw MCPPromptError.unknownPrompt(name)
        }

        return RenderedMCPPrompt(description: definition.description, text: text)
    }

    // MARK: 渲染

    private static func createPanel(_ arguments: [String: String]) throws -> String {
        let task = try required("task", prompt: "create-panel", in: arguments)
        let size = validatedSize(arguments["size"]) ?? "320x200"
        let position = validatedPosition(arguments["position"]) ?? "top-right"
        return """
        Build and display a PinShell overlay panel.

        Task:
        \(task)

        Window hints: size \(size), position \(position).

        \(authoringGuide)

        Workflow:
        1. Write one complete HTML document.
        2. Call pinshell_html with html and wait: true; pass size/position only when they should override the hints above.
        3. Reply with one line describing what is on screen. If the panel expects a response, call pinshell_poll_events with timeout_ms 10000 and handle the returned events.
        """
    }

    private static func interactivePanel(_ arguments: [String: String]) throws -> String {
        let task = try required("task", prompt: "interactive-panel", in: arguments)
        let options = trimmed(arguments["options"]) ?? "design labels that fit the task"
        return """
        Build a PinShell overlay panel that collects a decision or short input from the user and reports it back to you.

        Task:
        \(task)

        Choices: \(options)

        \(authoringGuide)

        Interaction rules:
        - Render real buttons or clickable cards; make them keyboard-accessible and show a visible focus state.
        - On activation, call pinshell.emit('decision', { id, label, value }) exactly once, then switch to a submitted state and disable further submission.
        - After load, call pinshell.emit('ready', { at: Date.now() }) so the agent knows the UI is live.
        - Acknowledge from the agent side with pinshell_emit('agent:message', {...}) or update the DOM with pinshell_eval; do not reload the page for small changes.

        Workflow: call pinshell_html with the complete document and wait: true, then call pinshell_poll_events with timeout_ms 10000 and keep polling while waiting for 'ready' or 'decision'. Act on the event and reply to the user.
        """
    }

    private static func liveMonitor(_ arguments: [String: String]) throws -> String {
        let task = try required("task", prompt: "live-monitor", in: arguments)
        let source = trimmed(arguments["source"])
            ?? "none specified - use data the agent pushes with pinshell_eval"
        let seconds = clampedInterval(arguments["interval"])
        let milliseconds = seconds * 1000
        return """
        Build a PinShell overlay panel that stays up to date.

        Task:
        \(task)

        Data source: \(source)
        Refresh interval: \(seconds) seconds.

        \(authoringGuide)

        Implementation rules:
        - For an https endpoint, refresh inside the page with setInterval(refresh, \(milliseconds)). Call await pinshell.fetch(url, {headers}) and parse the response; keep the last good value visible while a refresh is in flight.
        - On fetch failure, show a small, non-blocking error state and retry on the next tick. Never clear the panel because one request failed.
        - If the agent supplies the data, render a static shell and push updates with pinshell_eval; do not reload the page.
        - Render meaningful content immediately; do not block first paint on network I/O.

        Workflow: call pinshell_html with the complete document, then confirm what is visible. For agent-pushed updates, keep the panel open and call pinshell_eval as data arrives.
        """
    }

    private static func editTemplate(_ arguments: [String: String]) throws -> String {
        let name = try required("name", prompt: "edit-template", in: arguments)
        let changes = try required("changes", prompt: "edit-template", in: arguments)
        return """
        Update an existing PinShell template.

        Template file: \(name)
        Requested change:
        \(changes)

        Steps:
        1. Call pinshell_template_read with name "\(name)". If it does not exist, call pinshell_templates first and choose the closest file.
        2. Modify the complete HTML document. Preserve its <meta name="pinshell:*"> values, <title>, and <meta name="description"> unless the change explicitly overrides them. Preserve asset references (for example design-tokens.css) and the established visual style.
        3. Call pinshell_template_write with the full document. Writes are limited to flat .html/.htm files inside PinShell's templates folder.
        4. The console refreshes automatically and a currently shown template reloads in place. Confirm the file you wrote and what changed.

        If the change adds interactivity or live updates, follow this contract:
        \(authoringGuide)
        """
    }

    private static func authoringGuidePrompt() -> String {
        """
        Use this contract when writing HTML for PinShell.

        \(authoringGuide)

        Workflow: show a document with pinshell_html, update it with pinshell_eval, send events into it with pinshell_emit, and receive page events with pinshell_poll_events. Save reusable panels with pinshell_template_write.
        """
    }

    // MARK: 参数

    /// 把 BCP-47 标识符转成英文语言名；拿不到时回退到通用措辞。
    static func languageName(for identifier: String?) -> String {
        guard let identifier, !identifier.isEmpty else { return "the user's language" }
        let english = Locale(identifier: "en_US")
        return english.localizedString(forIdentifier: identifier)
            ?? english.localizedString(forLanguageCode: identifier)
            ?? identifier
    }

    private static func required(_ key: String,
                                 prompt: String,
                                 in arguments: [String: String]) throws -> String {
        guard let value = arguments[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            throw MCPPromptError.missingArgument(prompt: prompt, argument: key)
        }
        return value
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    /// 只接受合法尺寸，避免把用户输入原样写进 prompt。
    private static func validatedSize(_ raw: String?) -> String? {
        guard let raw = trimmed(raw), let size = WindowSize.parse(raw) else { return nil }
        return "\(NumberFormat.text(size.width))x\(NumberFormat.text(size.height))"
    }

    private static func validatedPosition(_ raw: String?) -> String? {
        guard let raw = trimmed(raw), WindowPosition.parse(raw) != nil else { return nil }
        return raw
    }

    private static func clampedInterval(_ raw: String?) -> Int {
        let value = Int(trimmed(raw) ?? "") ?? 60
        return min(max(value, 15), 3600)
    }

}
