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
        - Reply to the user in \(userLanguageName), the operating system language, and switch when the user writes in another language or asks. On-screen copy should follow window.pinshell.templateLanguage, then window.pinshell.languages, then window.pinshell.language (all BCP-47); if unavailable, use the same language as your reply.
        - Use PinShell proactively when a visual, interactive, or live response is clearer than text (progress, status, choices, confirmations, alerts); show the panel without asking first. Reuse an installed template when it fits, keep the panel small, dismiss it when done, and never duplicate chat text.
        - Rich media is welcome: inline SVG or https images, CSS/SVG/Canvas animation, emoji, short <audio>/<video> clips, and synthesized sound. Keep it light; make sound brief, quiet, and non-repeating; never block first paint.
        - Accessibility: use real buttons and controls, show a visible keyboard focus state, and honor prefers-reduced-motion for animation and sound-driven flourishes.
        """
    }

    /// HTML 作者契约；所有面板类 prompt 共用，避免各处描述漂移。
    public static var authoringGuide: String {
    """
    PinShell shows local HTML in a transparent, always-on-top macOS overlay with no browser \
    chrome, at a fixed window size. Two delivery targets:
    - pinshell_html writes a complete document into PinShell's agent folder and shows it.
      Only that folder is readable: inline CSS/JS and use data: URLs for assets.
      design-tokens.css and pinshell-i18n.js are NOT available there.
    - Templates live in PinShell's templates folder. PinShell installs design-tokens.css and
      pinshell-i18n.js next to templates; the app can also install first-party templates from
      the Online Template Library. Use pinshell_template_write and pinshell_template_show for
      reusable panels, localized copy, and anything worth keeping. If pinshell_templates is
      empty or has no fitting template, use pinshell_html with inline assets instead.

    Window metadata (put in <head>):
      <title>Panel title</title>
      <meta name="description" content="What this panel shows">
      <script type="application/json" id="pinshell:i18n">
      {
        "default": "en",
        "fallback": "en",
        "languages": {
          "en": {
            "meta": { "name": "Panel title", "description": "What this panel shows" },
            "ui": { "key": "English text" }
          }
        }
      }
      </script>
      <meta name="pinshell:size" content="320x120">
      <meta name="pinshell:position" content="bottom-right">
      <meta name="pinshell:passthrough" content="false">
      <meta name="pinshell:opacity" content="0.92">
      <meta name="pinshell:radius" content="18">
      <meta name="pinshell:order" content="10">
    Position accepts top-left|top|top-right|left|center|right|bottom-left|bottom|bottom-right, or "x,y".
    Order is the template library sort key; lower values sort first.

    Localization (for templates worth keeping):
      Put one JSON block in <head> (see above). Schema:
        default: the inline/default language.
        fallback: language used for missing keys (usually en).
        languages.<tag>.meta.name/description: template library metadata.
        languages.<tag>.ui: page copy. The default language's UI stays inline;
        non-default ui is merged over fallback, then inline copy.
      The app chooses a language from: selected template language → system preferences →
      fallback. window.pinshell.templateLanguage is the selected tag;
      window.pinshell.languages is the ordered preference list.
      Load <script src="pinshell-i18n.js"></script> after the block.
      Static copy: data-i18n="key"; attributes: data-i18n-placeholder|title|aria-label="key".
      Dynamic: PS.t('key', 'default copy', { name: value }); arrays: PS.list('key', [ … ]);
      raw data: PS.get('key', fallback); formatting locale: PS.locale.
      Non-default ui must cover every data-i18n / PS.t / PS.list / PS.get key.
      Legacy <meta name="pinshell:title" lang="en"> + window.PINSHELL_STRINGS still works,
      but prefer the JSON block. Append ?lang=en to preview a language in a browser.
      Agent-folder pages cannot load the helper: inline dictionaries and use
      window.pinshell.languages / navigator.languages.

    Base CSS:
      html, body { margin: 0; width: 100%; height: 100%; background: transparent; overflow: hidden; }
      body { font: 13px -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif; color: #fff; user-select: none; }
    Floating content needs its own background, padding, and rounded corners; the window itself is transparent.
    In templates, link design-tokens.css and reuse its --ps-* tokens instead of copying colors or radii.

    JS bridge (window.pinshell):
      version                     bridge version (2)
      session                     current panel session id
      language                    current app language (BCP-47)
      languages                   ordered template language preferences
      templateLanguage            language selected for this template, or null
      setSize(w, h) / setPosition('bottom-right' | x, y) / setPassthrough(bool) / setOpacity(0..1) / setRadius(px)
      getState() / setState(state) / patchState(patch)
                                  shared panel state; setState emits state:snapshot,
                                  patchState applies RFC 7386 and emits state:delta
      ready/input/submit/cancel(data)
                                  shorthand for ui:ready / ui:input / ui:submit / ui:cancel
      emit(name, data)            page -> agent; prefer namespaced names (ui:*)
      on(name, callback)          agent -> page, sent with pinshell_emit; callback receives data
      log(...)                    forwarded to the agent as a log event
      await fetch(url, {headers}) https-only GET, 15 s timeout, 2 MB cap, up to 20 headers
    Limits: bridge messages ≤ 64 KB; emitted names are truncated to 256 chars; log text to 4096 chars.
    Events carry { seq, ts, session, type, name, data }. type is the name prefix
    (ui, state, lifecycle, log, or a template namespace such as pet/system/todo).

    Delivery rules:
    - Call pinshell_templates first and reuse an installed template when it fits;
      pinshell_template_show accepts a file name or title and applies the template's metadata.
    - pinshell_html writes a complete document, shows it, and waits for load by default.
    - pinshell_eval updates the live DOM and returns the JSON result; prefer it over reloading.
    - pinshell_emit dispatches events into the page. Use pinshell_await_event to wait for a
      matching event (up to 30 s) and pinshell_poll_events to drain by cursor with filters.
    - pinshell_state returns the panel's shared state; prefer it over scraping the DOM.
    - Close the panel with pinshell_close when the task is done and the user no longer needs it.
    - Keep the panel compact and readable at its declared size, avoid layout shift, and respect
      prefers-reduced-motion.

    \(interactionGuide)
    """
    }

    /// 第一方模板与事件协议清单；供需要“先复用再新建”的 prompt 共用。
    /// 模板不再随 App 内置，必须先由用户在在线模板库安装。
    public static var templateLibraryGuide: String {
    """
    Library templates (list installed ones with pinshell_templates; prefer reusing one over new HTML):
      badge-carousel, goal-progress (in: bilibili:stats), decision-maker,
      todo (out: todo:changed), system-monitor (in: system:stats),
      desktop-pet (pet:* both ways),
      pomodoro (in: pomodoro:command; out: pomodoro:changed/complete/skip),
      ai-radio, gomoku, stock-board.
      These are commonly available from Console → Online Template Library; the user installs
      them manually. If pinshell_templates is empty or has no fitting template, build the panel
      with pinshell_html and inline its assets. Do not try to download or install templates
      yourself. pinshell_template_show accepts a file name or title and applies the template's
      metadata. pinshell_template_read returns the HTML, including any AGENT PROTOCOL or
      data-protocol comment — read it before pushing events.
    """
    }

    /// MCP `initialize` 的 server instructions（服务端与控制台展示共用）。
    public static var serverInstructions: String {
        """
        PinShell is an always-on-top HTML overlay on macOS. \
        Be proactive: when a visual, interactive, or live response is clearer than chat — \
        progress, status, comparisons, choices, confirmations, alerts — show a compact panel \
        without asking first; prefer buttons + pinshell_await_event over typed questions. \
        Keep panels small, close them when done, and never repeat what chat already says. \
        Call pinshell_templates first and reuse an installed template when it fits; read its \
        protocol comment before pushing events. pinshell_html renders HTML in an isolated \
        agent folder (inline its assets); pinshell_eval updates the live DOM; pinshell_emit and \
        pinshell_await_event / pinshell_poll_events exchange events (cursor + type/name filters); \
        pinshell_state reads the panel's shared state. \
        Window hints: <meta name="pinshell:size|position|passthrough|opacity|radius|order">. \
        Templates support pinshell:title/subtitle lang variants and pinshell-i18n.js; \
        window.pinshell.language is the app language. \
        window.pinshell: setSize, setPosition, setPassthrough, setOpacity, setRadius, \
        getState, setState, patchState, ready/input/submit/cancel, emit, on, log, and an \
        https-only fetch. \
        If the desktop pet is installed, it can be driven with pet:* events; use the pet-companion \
        prompt to connect it to your work. \
        Reply in \(userLanguageName) (the OS language) and write on-screen copy in the app \
        language; panels may use images, animation, sound, and video.
        """
    }

    public static let definitions: [MCPPromptDefinition] = [
        MCPPromptDefinition(
            name: "create-panel",
            title: "Create a panel",
            description: "Author a PinShell overlay panel, reusing an installed template when it fits, and display it.",
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
            description: "Build a panel that refreshes from an https endpoint or agent-pushed updates, reusing live templates when they fit.",
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
            name: "pet-companion",
            title: "Desktop pet companion",
            description: "Show the desktop pet and keep it in sync with your work through pet:* events.",
            arguments: [
                MCPPromptArgument(name: "task",
                                  description: "What you are working on, shown by the pet.",
                                  required: false)
            ]
        ),
        MCPPromptDefinition(
            name: "edit-template",
            title: "Edit a template",
            description: "Read, modify, and write a PinShell template while preserving metadata, localization, and agent protocols.",
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
            description: "The full PinShell HTML, window metadata, localization, JS bridge, and user-interaction contract.",
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
        case "pet-companion":
            text = try petCompanion(arguments)
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

        \(templateLibraryGuide)

        Workflow:
        1. Call pinshell_templates. If an installed template already covers the task, call
           pinshell_template_show with its file name and pass size/position only to override the
           hints; do not rewrite it. Otherwise write one complete HTML document.
        2. Call pinshell_html with html and wait: true; pass size/position only when they should
           override the hints above.
        3. Reply with one line describing what is on screen. If the panel expects a response,
           call pinshell_await_event with types ["ui"] and names ["ui:submit", "ui:cancel"]
           (wait_ms 30000) and handle the returned event. Use pinshell_poll_events to drain
           other events by cursor. Close it with pinshell_close when the user is done.
        """
    }

    private static func interactivePanel(_ arguments: [String: String]) throws -> String {
        let task = try required("task", prompt: "interactive-panel", in: arguments)
        let options = trimmed(arguments["options"]) ?? "none supplied - design 2-4 clear options that fit the task"
        return """
        Build a PinShell overlay panel that collects a decision or short input from the user and reports it back to you.

        Task:
        \(task)

        Choices: \(options)

        \(authoringGuide)

        Interaction rules:
        - Render real buttons or clickable cards; make them keyboard-accessible and show a visible focus state. Prefer choices over typing; trim and cap free-text input.
        - After load, call window.pinshell.ready({ at: Date.now(), choices: [...] }) so the agent knows the UI is live.
        - On activation, call window.pinshell.submit({ id, label, value }) exactly once, then switch to a submitted state and disable further submission.
        - Provide a cancel path: call window.pinshell.cancel({ at: Date.now() }) and leave the panel visible until the agent closes it.
        - Record UI progress with window.pinshell.setState({ phase, choice, ... }) or patchState({ ... }); the agent reads it with pinshell_state. Do not store the answer only in the DOM.
        - Listen with window.pinshell.on('agent:message', ...) for acknowledgements. Acknowledge from the agent side with pinshell_emit('agent:message', {...}) or update the DOM with pinshell_eval; do not reload the page for small changes.

        Workflow: call pinshell_html with the complete document and wait: true, then call pinshell_await_event with types ["ui"] and names ["ui:submit", "ui:cancel"] (wait_ms 30000). If it times out, read pinshell_state and await again while the user is still deciding. Act on the event, reply to the user, update the panel with pinshell_eval or pinshell_emit('agent:message', {...}), and close it with pinshell_close once the decision is handled and the user no longer needs it.
        """
    }

    private static func liveMonitor(_ arguments: [String: String]) throws -> String {
        let task = try required("task", prompt: "live-monitor", in: arguments)
        let source = trimmed(arguments["source"])
            ?? "none specified - render a calm static shell and push updates with pinshell_eval"
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
        - Reuse a live template when it fits instead of building from scratch:
          system-monitor.html (system:stats) or goal-progress.html (bilibili:stats).
          Show it with pinshell_template_show and push
          updates with pinshell_emit; read its data-protocol comment first with pinshell_template_read.
        - For an https endpoint, refresh inside the page with setInterval(refresh, \(milliseconds)).
          Call await pinshell.fetch(url, {headers}) and parse the response. It supports GET only,
          https only, a 15 s timeout, a 2 MB cap, and up to 20 headers.
        - Keep the last good value visible while a refresh is in flight. On failure, show a small,
          non-blocking error state and retry on the next tick; never clear the panel for one failure.
        - If the agent supplies the data, render a static shell and push updates with pinshell_eval;
          do not reload the page. If the template exposes an event protocol, prefer pinshell_emit.
        - Render meaningful content immediately; do not block first paint on network I/O.
        - Slow or pause polling while the page is hidden (document.hidden) and resume on visibility.

        Workflow: call pinshell_html with the complete document (or pinshell_template_show for an
        installed template), then confirm what is visible. For agent-pushed updates, keep the panel
        open and update it as data arrives; close it when the user asks or the task ends.
        """
    }

    private static func petCompanion(_ arguments: [String: String]) throws -> String {
        let task = trimmed(arguments["task"]) ?? "keep the user company while you work"
        return """
        Use PinShell's desktop pet as a live companion for this task.

        Task:
        \(task)

        Setup:
        1. Call pinshell_templates first. If desktop-pet.html is not listed, tell the user to open
           the console (⌘K) → Online Template Library and install Desktop Pet, then stop. Do not
           recreate the pet with pinshell_html.
        2. Call pinshell_template_show with name "desktop-pet.html" and wait: true.
        3. Announce yourself: pinshell_emit { event: "pet:hello", data: { name: "<your name>" } }.
        4. Read the template's AGENT PROTOCOL comment with pinshell_template_read when you need the full contract.

        Agent → page (pinshell_emit):
        - pet:say { text, mood?, tone?, duration? } — one short line (under ~40 characters); tone: calm|happy|excited|worried|thinking; mood: idle|happy|thinking|working|excited|sleepy|worried|alert.
        - pet:mood { mood, holdMs? } — body language before, during, and after work.
        - pet:task { label, progress?, status? } — status: running|done|failed|waiting; progress 0..1; done and failed auto-dismiss.
        - pet:animate { name } — jump|spin|shake|dance|wave|nod|dizzy.
        - pet:celebrate { text? } / pet:alert { text?, level? } — outcome feedback; keep the detail in chat.
        - pet:reply { requestId, text, mood? } — answer pet:ask.
        - pet:reset — clear the task, mood, and pending question.
        - agent:message { text } — legacy alias for pet:say.
        - window.PinShellPet exposes say/mood/animate/task/celebrate/alert/reset/state for pinshell_eval.

        Page → agent (pinshell_await_event / pinshell_poll_events):
        - pet:ready { version, mood, muted, affection, moods[], features[] } — the pet is live.
        - pet:tap { area, count, mood, affection }, pet:pet { affection, mood }, pet:ask { requestId, text, mood }, pet:sleep { at }, pet:wake { at }.

        Etiquette:
        - Keep it ambient: at most one update every ~10 seconds, and never repeat what chat already says.
        - Use the pet for mood and status; use a normal panel for anything longer than one line.
        - While the pet is visible and the user is waiting on you, call pinshell_await_event with types ["pet"] and names ["pet:ask", "pet:tap"] (wait_ms 30000) between steps. Answer pet:ask in the same turn, echoing requestId within ~10 seconds.
        - The pet works without an agent. Never make the task's success depend on it, and never block on a reply.

        Workflow:
        1. Show the pet and emit pet:hello; wait for pet:ready when you need its features or state.
        2. Before long work, emit pet:mood "thinking"; for multi-step jobs, emit pet:task with progress updates.
        3. On success, pet:celebrate with a short line; on failure, pet:alert and keep the detail in chat.
        4. While waiting for the user, call pinshell_await_event with types ["pet"] and names
           ["pet:ask", "pet:tap"] (wait_ms 30000) and react briefly.
        5. When done, emit pet:mood "happy" plus pet:say, or pet:reset if the pet should rest.
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
        1. Call pinshell_template_read with name "\(name)". If it does not exist, call
           pinshell_templates first and choose the closest file.
        2. Modify the complete HTML document. Preserve unless the change explicitly overrides:
           - <title>, <meta name="description">, and every <meta name="pinshell:*"> value,
             including size/position/passthrough/opacity/radius/order;
           - <html lang> and the pinshell:title/pinshell:subtitle variants for other languages;
           - design-tokens.css and pinshell-i18n.js references, PINSHELL_STRINGS dictionaries,
             and data-i18n keys;
           - the established visual style and asset references;
           - AGENT PROTOCOL / data-protocol comments and event names (pet:*, system:stats,
             obs:status, bilibili:stats, pomodoro:command). Update them when the protocol changes.
        3. When adding UI copy, update the inline default text and the non-default language
           dictionaries together so translations do not drift.
        4. Call pinshell_template_write with the full document. Writes are limited to flat
           .html/.htm files inside PinShell's templates folder, up to 512 KB.
        5. The console refreshes automatically and a currently shown template reloads in place.
           Confirm the file you wrote and what changed.

        If the change adds interactivity or live updates, follow this contract:
        \(authoringGuide)
        """
    }

    private static func authoringGuidePrompt() -> String {
        """
        Use this contract when authoring HTML for PinShell.

        \(authoringGuide)

        \(templateLibraryGuide)

        Workflow: check pinshell_templates first; show a document with pinshell_html (or a
        template with pinshell_template_show), update it with pinshell_eval, send events into it
        with pinshell_emit, and receive page events with pinshell_await_event /
        pinshell_poll_events. Read shared state with pinshell_state. Save reusable panels with
        pinshell_template_write, and close panels with pinshell_close when done.
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
