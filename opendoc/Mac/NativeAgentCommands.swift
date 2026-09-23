#if os(macOS)
import Foundation
import CryptoKit

/// JSON operations share DockStore validation, persistence, undo, and live updates.
@MainActor
final class NativeAgentCommands {
    private let store: DockStore
    private let visible: (UUID) -> Bool
    private let setVisible: (UUID, Bool) -> Void

    init(store: DockStore, visible: @escaping (UUID) -> Bool, setVisible: @escaping (UUID, Bool) -> Void) {
        self.store = store; self.visible = visible; self.setVisible = setVisible
    }

    private func object<T: Encodable>(_ value: T) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as! [String: Any]
    }
    private func snapshot() throws -> [String: Any] {
        ["archive": try object(store.archive), "visibleDockIDs": store.archive.profiles.filter { visible($0.id) }.map { $0.id.uuidString }]
    }
    private func revision() throws -> String {
        SHA256.hash(data: try JSONSerialization.data(withJSONObject: snapshot(), options: [.sortedKeys])).map { String(format: "%02x", $0) }.joined()
    }
    private func fail(_ text: String) -> NSError { AgentTransport.failure(text) }
    private func isBoolean(_ value: Any) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }
    private func id(_ value: Any?, name: String) throws -> UUID {
        guard let value = value as? String, let id = UUID(uuidString: value) else { throw fail("Provide a UUID for \(name). Use state to discover IDs.") }
        return id
    }
    private func dock(_ value: Any?) throws -> DockProfile {
        let id = try id(value, name: "dockID")
        guard let profile = store.archive.profiles.first(where: { $0.id == id }) else { throw fail("Dock not found.") }
        return profile
    }
    private func widget(_ value: Any?) throws -> (DockProfile, Int) {
        let id = try id(value, name: "itemID")
        for profile in store.archive.profiles {
            if let index = profile.items.firstIndex(where: { $0.id == id && $0.kind == .widget }) { return (profile, index) }
        }
        throw fail("Widget not found.")
    }
    private func rejectUnknown(_ value: [String: Any], allowed: Set<String>) throws {
        let unknown = Set(value.keys).subtracting(allowed)
        if !unknown.isEmpty { throw fail("Unknown fields: \(unknown.sorted().joined(separator: ", ")). See schema.") }
    }
    private func merge(_ base: [String: Any], _ patch: [String: Any], allowed: Set<String>? = nil) throws -> [String: Any] {
        try rejectUnknown(patch, allowed: allowed ?? Set(base.keys))
        var result = base
        for (key, value) in patch {
            if key == "actions", let actions = value as? [[String: Any]] {
                result[key] = try actions.map { action in
                    try rejectUnknown(action, allowed: ["id", "title", "script"])
                    var action = action
                    if action["id"] == nil { action["id"] = UUID().uuidString }
                    return action
                }
                continue
            }
            if let nested = value as? [String: Any], let existing = base[key] as? [String: Any], !["state", "initialState"].contains(key) {
                result[key] = try merge(existing, nested)
            } else { result[key] = value }
        }
        return result
    }
    private func patched<T: Codable>(_ value: T, patch: [String: Any], allowed: Set<String>? = nil) throws -> T {
        let merged = try merge(object(value), patch, allowed: allowed)
        return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: merged))
    }
    private func custom(_ patch: [String: Any]) throws -> CustomWidgetConfiguration {
        let config = try patched(CustomWidgetConfiguration(), patch: patch)
        try config.validate()
        return config
    }
    private func validate(_ profile: DockProfile) throws {
        var archive = store.archive
        guard let index = archive.profiles.firstIndex(where: { $0.id == profile.id }) else { throw fail("Dock not found.") }
        archive.profiles[index] = profile
        try archive.validate()
    }

    func handle(_ data: Data) async -> Data {
        do {
            guard let request = try JSONSerialization.jsonObject(with: data) as? [String: Any], let op = request["op"] as? String else { throw fail("Expected a JSON object with op.") }
            try rejectUnknown(request, allowed: ["op", "params", "dryRun", "ifRevision"])
            if let value = request["dryRun"], !isBoolean(value) { throw fail("dryRun must be boolean.") }
            let dryRun = request["dryRun"] as? Bool ?? false
            if let expected = request["ifRevision"] {
                guard let expected = expected as? String, expected == (try revision()) else { throw fail("Revision conflict. Read state and reapply the edit to the current configuration.") }
            }
            guard request["params"] == nil || request["params"] is [String: Any] else { throw fail("params must be an object.") }
            let params = request["params"] as? [String: Any] ?? [:]
            let result: [String: Any]
            switch op {
            case "state":
                try rejectUnknown(params, allowed: [])
                result = try snapshot()
            case "schema":
                try rejectUnknown(params, allowed: [])
                result = try schema()
            case "widget.preview":
                try rejectUnknown(params, allowed: ["custom"])
                guard let patch = params["custom"] as? [String: Any] else { throw fail("Provide custom configuration.") }
                let output = try await NativeCustomWidgetData.shared.preview(custom(patch))
                result = try object(output)
            case "widget.add":
                try rejectUnknown(params, allowed: ["dockID", "kind", "patch"])
                var profile = try dock(params["dockID"])
                guard let name = params["kind"] as? String, let kind = WidgetKind(rawValue: name) else { throw fail("Unknown widget kind. See schema.") }
                let item = try edit(DockItem.widget(kind), params["patch"])
                profile.items.append(item)
                try validate(profile)
                if !dryRun { try store.update(profile) }
                result = try object(item)
            case "widget.update", "widget.remove":
                try rejectUnknown(params, allowed: op == "widget.update" ? ["itemID", "patch"] : ["itemID"])
                var (profile, index) = try widget(params["itemID"])
                let item: DockItem
                if op == "widget.update" { item = try edit(profile.items[index], params["patch"]); profile.items[index] = item }
                else { item = profile.items.remove(at: index) }
                try validate(profile)
                if !dryRun { try store.update(profile) }
                result = try object(item)
            case "dock.update":
                try rejectUnknown(params, allowed: ["dockID", "patch", "visible"])
                var profile = try dock(params["dockID"])
                if let value = params["patch"] {
                    guard let patch = value as? [String: Any] else { throw fail("patch must be an object.") }
                    profile = try patched(profile, patch: patch, allowed: ["name", "symbol", "color", "appearance"])
                }
                if let value = params["visible"], !isBoolean(value) { throw fail("visible must be boolean.") }
                try validate(profile)
                if !dryRun {
                    try store.update(profile)
                    if let shown = params["visible"] as? Bool { setVisible(profile.id, shown) }
                }
                result = try object(profile)
            default: throw fail("Unknown operation \(op). Use schema to discover supported operations.")
            }
            return try JSONSerialization.data(withJSONObject: ["ok": true, "result": result, "revision": revision(), "dryRun": dryRun], options: [.sortedKeys, .prettyPrinted])
        } catch {
            return (try? JSONSerialization.data(withJSONObject: ["ok": false, "error": error.localizedDescription, "revision": (try? revision()) ?? ""], options: [.sortedKeys])) ?? Data()
        }
    }

    private func edit(_ item: DockItem, _ value: Any?) throws -> DockItem {
        guard let patch = value as? [String: Any] else { throw fail("Provide a patch object.") }
        let allowed: Set<String> = ["title", "symbol", "color", "url", "note", "checklist", "count", "countDay", "timeZone", "duration", "remaining", "startedAt", "deadline", "web", "custom"]
        var base = try object(item)
        // Seed optional configuration so partial edits get defaults and unknown keys are rejected.
        if patch["custom"] is [String: Any] {
            guard item.widget == .custom else { throw fail("custom configuration requires a custom widget.") }
            base["custom"] = try object(item.custom ?? CustomWidgetConfiguration())
        }
        if patch["web"] is [String: Any] {
            guard item.widget == .webValue else { throw fail("web configuration requires a webValue widget.") }
            base["web"] = try object(item.web ?? WebWidgetConfiguration())
        }
        let merged = try merge(base, patch, allowed: allowed)
        return try JSONDecoder().decode(DockItem.self, from: JSONSerialization.data(withJSONObject: merged))
    }

    private func schema() throws -> [String: Any] {
        ["version": 1,
         "commandHelp": try NativeAgentHelp.catalog(),
         "operations": [
            "state": "{} -> archive and visibleDockIDs",
            "schema": "{} -> capabilities and defaults",
            "widget.add": "{dockID, kind, patch} -> created widget",
            "widget.update": "{itemID, patch} -> updated widget",
            "widget.remove": "{itemID} -> removed widget",
            "widget.preview": "{custom} -> value, detail, optional progress; may fetch HTTPS or run an explicitly enabled local command",
            "dock.update": "{dockID, patch?, visible?} -> updated dock; patch: name, symbol, color, appearance"
         ],
         "widgetKinds": WidgetKind.allCases.map(\.rawValue),
         "widgetPatchFields": ["title", "symbol", "color", "url", "note", "checklist", "count", "countDay", "timeZone", "duration", "remaining", "startedAt", "deadline", "web", "custom"],
         "widgetDefaults": try object(DockItem.widget(.custom)),
         "customTemplates": ["counter": try object(CustomWidgetConfiguration()), "water": try object(CustomWidgetConfiguration.water()), "webpage": try object(CustomWidgetConfiguration.webpage()), "command": try object(CustomWidgetConfiguration.commandTemplate()), "codex": try object(CustomWidgetConfiguration.codexBar(provider: "codex")), "claude": try object(CustomWidgetConfiguration.codexBar(provider: "claude"))],
         "appearance": ["position": ["Bottom", "Left", "Right"], "material": ["Glass", "Light", "Dark"], "size": ["minimum": 36, "maximum": 88], "glassStyle": ["Clear", "Regular"], "glassTint": ["minimum": 0, "maximum": 1], "autoHide": "boolean", "showLabels": "boolean", "wallpaper": ["Meadow", "Dusk", "Ocean"]],
         "notes": ["UUIDs come from state. No name matching.", "Patch objects merge; arrays, state and initialState replace. null clears optional fields.", "Unknown fields are rejected. IDs and widget kind cannot be changed.", "dryRun validates mutations without saving. Preview executes scripts and may fetch its URL or execute an explicitly enabled local command.", "ifRevision rejects edits based on stale state. No automatic retries of mutations.", "Dates use JSONEncoder seconds since 2001-01-01 UTC.", "UI is native and constrained to supported appearance fields; no arbitrary CSS or native view injection."]]
    }
}

enum NativeAgentCLI {
    static func run(_ arguments: [String]) -> Int32 {
        do {
            if arguments.isEmpty || arguments.first == "help" || arguments.contains("--help") || arguments.contains("-h") {
                let topics = arguments.filter { !["help", "--help", "-h", "--json"].contains($0) }
                guard topics.count <= 1 else { throw AgentTransport.failure("Usage: opendoc help [COMMAND] [--json]") }
                print(try NativeAgentHelp.render(command: topics.first, json: arguments.contains("--json")))
                return 0
            }
            let op = arguments[0]
            guard NativeAgentHelp.commands.contains(op) else { throw AgentTransport.failure("Unknown command \(op). Run opendoc help for commands and examples.") }
            var request: [String: Any] = ["op": op]
            var index = 1
            while index < arguments.count {
                switch arguments[index] {
                case "--dry-run": request["dryRun"] = true
                case "--input", "--if-revision":
                    let option = arguments[index]; index += 1
                    guard index < arguments.count else { throw AgentTransport.failure("Missing value for \(option).") }
                    if option == "--if-revision" { request["ifRevision"] = arguments[index] }
                    else {
                        let input = arguments[index] == "-" ? FileHandle.standardInput : try FileHandle(forReadingFrom: URL(fileURLWithPath: arguments[index]))
                        defer { if arguments[index] != "-" { try? input.close() } }
                        var data = Data()
                        while data.count <= 1_048_576, let chunk = try input.read(upToCount: min(8192, 1_048_577 - data.count)), !chunk.isEmpty { data.append(chunk) }
                        guard data.count <= 1_048_576, let params = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AgentTransport.failure("Input must be a JSON object under 1 MB.") }
                        request["params"] = params
                    }
                default: throw AgentTransport.failure("Unknown CLI option \(arguments[index]).")
                }
                index += 1
            }
            let response = try AgentTransport.request(JSONSerialization.data(withJSONObject: request))
            FileHandle.standardOutput.write(response + Data([10]))
            let value = try JSONSerialization.jsonObject(with: response) as? [String: Any]
            return value?["ok"] as? Bool == true ? 0 : 1
        } catch {
            let result: [String: Any] = ["ok": false, "error": error.localizedDescription]
            if let data = try? JSONSerialization.data(withJSONObject: result) { FileHandle.standardOutput.write(data + Data([10])) }
            return 1
        }
    }
}
#endif
