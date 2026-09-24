import Foundation

struct CustomWidgetAction: Codable, Equatable, Sendable {
    var id = UUID()
    var title: String
    var script: String
}

struct CustomWidgetConfiguration: Codable, Equatable, Sendable {
    enum Source: String, Codable, Sendable { case local, webpage, command }
    var source: Source = .local
    var command = WidgetCommandConfiguration()
    var endpoint = ""
    var selector = ""
    var attribute = ""
    var refreshInterval: TimeInterval = 300
    var initialState: [String: Double] = ["count": 0]
    var state: [String: Double] = ["count": 0]
    var stateDay = ""
    var resetDaily = false
    var renderScript = "return { value: String(state.count || 0), detail: 'Clicks recorded' };"
    var actions: [CustomWidgetAction] = [
        .init(title: "+1", script: "state.count = (state.count || 0) + 1; return state;"),
        .init(title: "Undo", script: "state.count = Math.max(0, (state.count || 0) - 1); return state;"),
        .init(title: "Reset", script: "state.count = 0; return state;")
    ]

    init() {}

    // Older workspaces predate command sources. Never enable local execution on migration.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        source = try values.decode(Source.self, forKey: .source)
        command = try values.decodeIfPresent(WidgetCommandConfiguration.self, forKey: .command) ?? .init()
        endpoint = try values.decode(String.self, forKey: .endpoint)
        selector = try values.decode(String.self, forKey: .selector)
        attribute = try values.decode(String.self, forKey: .attribute)
        refreshInterval = try values.decode(TimeInterval.self, forKey: .refreshInterval)
        initialState = try values.decode([String: Double].self, forKey: .initialState)
        state = try values.decode([String: Double].self, forKey: .state)
        stateDay = try values.decode(String.self, forKey: .stateDay)
        resetDaily = try values.decode(Bool.self, forKey: .resetDaily)
        renderScript = try values.decode(String.self, forKey: .renderScript)
        actions = try values.decode([CustomWidgetAction].self, forKey: .actions)
    }

    nonisolated func effectiveState(day: String) -> [String: Double] {
        resetDaily && stateDay != day ? initialState : state
    }

    nonisolated func validate() throws {
        try command.validate(requireExecutable: source == .command)
        guard endpoint.count <= 4096, selector.count <= 512, attribute.count <= 128,
              refreshInterval.isFinite, (60...3600).contains(refreshInterval),
              !renderScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              renderScript.utf8.count <= 16_384, actions.count <= 4,
              Set(actions.map(\.id)).count == actions.count,
              actions.allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.title.count <= 40 && $0.script.utf8.count <= 4096 }),
              Self.validState(initialState), Self.validState(state) else {
            throw CustomWidgetError.message("Use up to four named buttons, 32 numeric state values, and a render function under 16 KB.")
        }
        if source == .webpage {
            guard let url = URL(string: endpoint), url.scheme == "https", url.host?.isEmpty == false,
                  url.user == nil, url.password == nil, !selector.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CustomWidgetError.message("Enter an HTTPS webpage URL and a CSS selector, such as .price or #total.")
            }
        }
    }

    nonisolated static func validState(_ state: [String: Double]) -> Bool {
        state.count <= 32 && state.allSatisfy { !$0.key.isEmpty && $0.key.count <= 64 && $0.value.isFinite && abs($0.value) <= 1e12 }
    }

    static func water() -> Self {
        var result = Self()
        result.initialState = ["count": 0, "goal": 8]; result.state = result.initialState
        result.resetDaily = true
        result.renderScript = """
        const count = state.count || 0;
        const goal = state.goal || 8;
        return { value: `${count} / ${goal}`, detail: 'Glasses today', progress: count / goal };
        """
        result.actions[0].title = "Add a Glass"
        return result
    }

    static func webpage() -> Self {
        var result = Self()
        result.source = .webpage; result.initialState = [:]; result.state = [:]; result.actions = []
        result.renderScript = "return { value: input.text.trim(), detail: 'From webpage' };"
        return result
    }

    static func commandTemplate() -> Self {
        var result = Self()
        result.source = .command; result.initialState = [:]; result.state = [:]; result.actions = []
        result.command.executable = "/bin/bash"
        result.command.arguments = ["-c", "printf '%s\\n' '{\"value\":\"Hello\",\"detail\":\"Command widget\"}'"]
        result.renderScript = "return JSON.parse(input.text);"
        return result
    }

    static func codexBar(provider: String) -> Self {
        var result = commandTemplate()
        result.command.executable = "/Applications/CodexBar.app/Contents/Helpers/CodexBarCLI"
        result.command.arguments = ["usage", "--provider", provider, "--source", "oauth", "--format", "json"]
        result.renderScript = """
        const rows = JSON.parse(input.text);
        const row = rows.find(r => r.provider === '\(provider)');
        if (!row || row.error || !row.usage) throw new Error('Usage unavailable. Check this account in CodexBar.');
        const usage = row.usage;
        const window = usage.primary || usage.secondary;
        if (!window || typeof window.usedPercent !== 'number') throw new Error('No quota window reported.');
        const remaining = Math.max(0, Math.min(100, 100 - window.usedPercent));
        const label = window.windowMinutes === 10080 ? 'Weekly' : window.windowMinutes === 300 ? '5h' : 'Quota';
        const reset = window.resetsAt ? Date.parse(window.resetsAt) : NaN;
        const minutes = Math.max(0, Math.ceil((reset - Date.now()) / 60000));
        const when = Number.isFinite(minutes) ? (minutes >= 1440 ? Math.ceil(minutes / 1440) + 'd' : minutes >= 60 ? Math.floor(minutes / 60) + 'h ' + minutes % 60 + 'm' : minutes + 'm') : '';
        return {
          value: Math.round(remaining) + '% left',
          detail: '\(provider == "claude" ? "Claude" : "Codex") · ' + label + (when ? ' · ' + when : ''),
          progress: remaining / 100,
          style: 'ring', tint: 'level',
          apps: [\(provider == "claude" ? "'com.anthropic.claudefordesktop'" : "'com.openai.codex', 'com.openai.chat'")],
          symbol: '\(provider == "claude" ? "sparkle" : "chevron.left.forwardslash.chevron.right")'
        };
        """
        return result
    }
}

struct CustomWidgetInput: Codable, Equatable, Sendable {
    var text = ""
    var matches: [String] = []
}

struct CustomWidgetOutput: Codable, Equatable, Sendable {
    var value: String
    var detail: String = ""
    var progress: Double?
    /// Optional presentation, all chosen by the display function:
    /// `style` "ring" or "bar", `tint` a named colour or "level" (green, then
    /// yellow, then red as progress falls), `symbol` an SF Symbol name, and
    /// `apps` bundle identifiers whose installed icon is shown, first match wins.
    var style: String?
    var tint: String?
    var symbol: String?
    var apps: [String]?

    nonisolated static let styles = ["ring", "bar"]
    nonisolated static let tints = ["level", "blue", "purple", "pink", "red", "orange", "yellow", "green", "teal", "indigo", "gray"]

    nonisolated init(value: String, detail: String = "", progress: Double? = nil, style: String? = nil, tint: String? = nil, symbol: String? = nil, apps: [String]? = nil) {
        self.value = value; self.detail = detail; self.progress = progress
        self.style = style; self.tint = tint; self.symbol = symbol; self.apps = apps
    }
}

enum CustomWidgetError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
