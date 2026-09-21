import Foundation

struct CustomWidgetAction: Codable, Equatable, Sendable {
    var id = UUID()
    var title: String
    var script: String
}

struct CustomWidgetConfiguration: Codable, Equatable, Sendable {
    enum Source: String, Codable, Sendable { case local, webpage }
    var source: Source = .local
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

    nonisolated func effectiveState(day: String) -> [String: Double] {
        resetDaily && stateDay != day ? initialState : state
    }

    nonisolated func validate() throws {
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
}

struct CustomWidgetInput: Codable, Equatable, Sendable {
    var text = ""
    var matches: [String] = []
}

struct CustomWidgetOutput: Codable, Equatable, Sendable {
    var value: String
    var detail: String = ""
    var progress: Double?
}

enum CustomWidgetError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
