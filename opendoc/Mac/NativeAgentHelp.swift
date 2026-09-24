#if os(macOS)
import Foundation

/// Shipped with the executable, so help also works while the app is closed.
enum NativeAgentHelp {
    static let commands = ["state", "schema", "widget.add", "widget.update", "widget.remove", "widget.preview", "dock.update"]
    static let flags = [
        "--input FILE|-": "Read a JSON params object from a file or stdin. Do not wrap it in op/params.",
        "--dry-run": "Validate add/update/remove without changing the dock. Does not prevent widget.preview from fetching its URL or executing an enabled local command.",
        "--if-revision HASH": "Apply only if the state revision still matches. Read state again on conflict.",
        "--help, -h": "Explain this command without connecting to the app.",
        "--json": "With help only: return machine-readable documentation."
    ]
    static let workflow = [
        "Run opendoc state. Choose a dock UUID from result.archive.profiles and keep revision.",
        "Run opendoc help COMMAND for fields and an example. Use schema for widget kinds and defaults.",
        "Preview custom scripts with widget.preview; validate edits with --dry-run.",
        "Apply the edit with --if-revision HASH, then read state to verify it.",
        "On timeout, read state before retrying. The edit may already have applied."
    ]
    static let patchRules = "Patch objects merge. Arrays and state/initialState dictionaries replace. Omitted fields stay unchanged; null clears optional fields. IDs and widget kinds cannot change. Unknown fields are rejected. Dates are seconds since 2001-01-01 UTC."

    static func command(_ name: String) throws -> [String: Any] {
        let description: String
        let fields: [String: String]
        let required: [String]
        let example: [String: Any]
        let result: String
        switch name {
        case "state":
            description = "Read docks, widget configuration, visible dock IDs, and the current revision."
            fields = [:]; required = []; example = [:]
            result = "result.archive contains profiles and activeID; result.visibleDockIDs lists visible docks. revision is a concurrency token."
        case "schema":
            description = "Discover supported widget kinds, configuration defaults, templates, appearance limits, and command help."
            fields = [:]; required = []; example = [:]
            result = "result contains widgetKinds, widgetDefaults, customTemplates, appearance, commandHelp, and notes."
        case "widget.add":
            description = "Add one widget to an existing dock and return its generated ID."
            fields = ["dockID": "Required UUID from state; names are not accepted.", "kind": "Required widget kind from schema.widgetKinds, e.g. custom, clock, hydration, webValue.", "patch": "Required object. Use {} for defaults, or set title, custom, web, and other supported widget fields."]
            required = ["dockID", "kind", "patch"]
            example = ["dockID": "DOCK_UUID", "kind": "custom", "patch": ["title": "Water cups", "custom": ["state": ["count": 0], "initialState": ["count": 0], "renderScript": "return { value: state.count + ' glasses', detail: 'Today', progress: state.count / 8 };", "actions": [["title": "Add a Glass", "script": "state.count += 1; return state;"]]]]]
            result = "result is the created widget. Save result.id for later edits. Missing action IDs are generated."
        case "widget.update":
            description = "Change selected fields of an existing widget without replacing its other configuration."
            fields = ["itemID": "Required UUID from a profile's items in state.", "patch": "Required partial widget object. Supported fields: title, symbol, color, url, note, checklist, count, countDay, timeZone, duration, remaining, startedAt, deadline, web, custom. custom/web require the matching widget kind."]
            required = ["itemID", "patch"]
            example = ["itemID": "ITEM_UUID", "patch": ["title": "Daily water", "custom": ["state": ["count": 3]]]]
            result = "result is the updated widget, including unchanged fields. Set both initialState and state when resetting a counter configuration."
        case "widget.remove":
            description = "Remove one widget. The normal app Undo history records the removal."
            fields = ["itemID": "Required UUID of a widget from state."]
            required = ["itemID"]; example = ["itemID": "ITEM_UUID"]
            result = "result is the removed widget. --dry-run validates the target without removing it."
        case "widget.preview":
            description = "Evaluate a custom widget without saving it. Webpage sources fetch the configured HTTPS URL. Command sources execute the local program when command.enabled is true, including with --dry-run."
            fields = ["custom": "Required partial custom configuration. Fields: source (local/webpage/command), command {enabled (default false), executable (absolute path), arguments (string array), timeout (1...25 seconds, default 20)}, endpoint, selector, attribute, refreshInterval (60...3600 seconds), initialState, state, stateDay, resetDaily, renderScript, actions. State contains numbers; actions contain title, script, and optional id."]
            required = ["custom"]
            example = ["custom": ["state": ["count": 3], "renderScript": "return { value: state.count + ' glasses', detail: 'Today', progress: state.count / 8 };"]]
            result = "result contains value, detail, and optional progress (0...1). The render function may also return style (ring/bar), tint (level/blue/purple/pink/red/orange/yellow/green/teal/indigo/gray; level turns green, yellow, then red as progress falls), symbol (an SF Symbol name, also used as the tile's glyph), and apps (up to 4 bundle identifiers; the first installed app's icon is shown, never launched). Unsupported presentation values are ignored rather than failing the widget. Code receives state, input.text, input.matches. It has no file/shell/network APIs and stops after 2 seconds. HTML extraction reads returned HTML without site scripts or browser login."
        case "dock.update":
            description = "Change a dock's supported native appearance, name, or visibility."
            fields = ["dockID": "Required UUID from state.", "patch": "Optional object: name, symbol, color, appearance. Appearance: position (Bottom/Left/Right), material (Glass/Light/Dark), glassStyle (Clear/Regular), glassTint (0...1, tint strength), tintColor (Graphite/Accent/Blue/Purple/Pink/Red/Orange/Yellow/Green, colour of the tint), size (36...88 points), autoHide (boolean), showLabels (boolean), wallpaper (Meadow/Dusk/Ocean, workspace preview only).", "visible": "Optional boolean. Hiding the last visible dock restores Apple's Dock."]
            required = ["dockID"]
            example = ["dockID": "DOCK_UUID", "patch": ["appearance": ["position": "Bottom", "material": "Glass", "size": 48, "autoHide": true]]]
            result = "result is the updated dock. Arbitrary CSS or native view injection is not supported."
        default: throw AgentTransport.failure("Unknown command \(name). Run opendoc help for the command list.")
        }
        return ["command": name, "description": description, "required": required, "fields": fields, "example": example, "result": result]
    }

    static func catalog() throws -> [String: Any] {
        try Dictionary(uniqueKeysWithValues: commands.map { ($0, try command($0)) })
    }

    static func render(command name: String?, json: Bool) throws -> String {
        let entry = try name.map { try command($0) }
        if json {
            let documented = try entry.map { [$0["command"] as! String: $0] } ?? catalog()
            let doc: [String: Any] = ["version": 1, "usage": "opendoc COMMAND [--input FILE|-] [--dry-run] [--if-revision HASH]", "flags": flags, "workflow": workflow, "patchRules": patchRules, "commands": documented, "exitCodes": ["0": "success", "1": "error; see JSON error field"], "requiresRunningApp": true]
            return String(data: try JSONSerialization.data(withJSONObject: doc, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!
        }
        var lines = ["Open Doc agent CLI", "Usage: opendoc \(name ?? "COMMAND") [--input FILE|-] [--dry-run] [--if-revision HASH]", ""]
        if let entry, let name {
            lines += [entry["description"] as! String, "", "Input fields:"]
            let fields = entry["fields"] as! [String: String]
            lines += fields.isEmpty ? ["  No input required."] : fields.keys.sorted().map { "  \($0): \(fields[$0]!)" }
            let example = entry["example"] as! [String: Any]
            lines += ["", "Example (replace UUID placeholders with IDs from opendoc state):"]
            if example.isEmpty { lines.append("  opendoc \(name)") }
            else {
                let body = String(data: try JSONSerialization.data(withJSONObject: example, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]), encoding: .utf8)!
                lines += ["opendoc \(name) --input -\(name == "widget.preview" ? "" : " --dry-run") <<'JSON'", body, "JSON"]
            }
            lines += ["", "Result:", entry["result"] as! String, "", patchRules]
        } else {
            lines.append("Commands:")
            for name in commands { lines.append("  \(name)  \((try command(name))["description"] as! String)") }
            lines += ["", "Start here:"] + workflow.enumerated().map { "  \($0.offset + 1). \($0.element)" }
        }
        lines += ["", "Options:"] + flags.keys.sorted().map { "  \($0)  \(flags[$0]!)" }
        lines += ["", "opendoc help COMMAND and opendoc COMMAND --help explain a command.", "opendoc help --json returns offline machine-readable help.", "Commands require the app to be running; help works offline.", "Commands output JSON. Exit 0 means success; exit 1 means failure. Read error before retrying."]
        return lines.joined(separator: "\n")
    }
}
#endif
