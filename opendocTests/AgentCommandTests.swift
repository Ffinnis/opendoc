#if os(macOS)
import XCTest
@testable import opendoc

@MainActor
final class AgentCommandTests: XCTestCase {
    func testEveryCommandHasOfflineHelpAndExamples() throws {
        for command in NativeAgentHelp.commands {
            let text = try NativeAgentHelp.render(command: command, json: false)
            XCTAssertTrue(text.contains("Usage: opendoc \(command)"))
            XCTAssertTrue(text.contains("Example"))
            let json = try NativeAgentHelp.render(command: command, json: true)
            let help = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
            XCTAssertNotNil((help["commands"] as? [String: Any])?[command])
        }
        XCTAssertThrowsError(try NativeAgentHelp.render(command: "unknown", json: false))
    }

    func testGlassAppearanceMigrationAndAgentValidation() async throws {
        let legacy = Data(#"{"position":"Bottom","material":"Glass","wallpaper":"Meadow","size":60,"autoHide":true,"showLabels":true}"#.utf8)
        let appearance = try JSONDecoder().decode(DockAppearance.self, from: legacy)
        XCTAssertEqual(appearance.glassStyle, "Regular")
        XCTAssertEqual(appearance.glassTint, 0)
        XCTAssertEqual(appearance.tintColor, "Graphite", "Docks saved before tint colours keep their dark tint")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("glass-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = DockStore(fileURL: url)
        let commands = NativeAgentCommands(store: store, visible: { _ in false }, setVisible: { _, _ in })
        func update(_ patch: [String: Any]) async throws -> Bool {
            let request: [String: Any] = ["op": "dock.update", "params": ["dockID": store.active.id.uuidString, "patch": ["appearance": patch]]]
            let result = await commands.handle(try JSONSerialization.data(withJSONObject: request))
            return (try JSONSerialization.jsonObject(with: result) as? [String: Any])?["ok"] as? Bool == true
        }
        let accepted = try await update(["glassStyle": "Clear", "glassTint": 0.35, "tintColor": "Blue"])
        XCTAssertTrue(accepted)
        let restored = DockStore(fileURL: url)
        XCTAssertEqual(restored.active.appearance.glassStyle, "Clear")
        XCTAssertEqual(restored.active.appearance.glassTint, 0.35)
        XCTAssertEqual(restored.active.appearance.tintColor, "Blue")
        let before = try store.exportData()
        for patch: [String: Any] in [["glassTint": -0.1], ["glassTint": 1.1], ["glassStyle": "Unknown"], ["tintColor": "Teal"], ["tintColor": 3]] {
            let accepted = try await update(patch)
            XCTAssertFalse(accepted)
            XCTAssertEqual(try store.exportData(), before)
        }
    }

    func testSchemaAndHelpListEveryTintColour() async throws {
        let help = try NativeAgentHelp.render(command: "dock.update", json: false)
        for colour in DockAppearance.tintColors { XCTAssertTrue(help.contains(colour), colour) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tint-schema-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let commands = NativeAgentCommands(store: DockStore(fileURL: url), visible: { _ in false }, setVisible: { _, _ in })
        let data = await commands.handle(try JSONSerialization.data(withJSONObject: ["op": "schema"]))
        let response = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let appearance = try XCTUnwrap(result["appearance"] as? [String: Any])
        XCTAssertEqual(appearance["tintColor"] as? [String], DockAppearance.tintColors)
        let output = try XCTUnwrap(result["customOutput"] as? [String: Any])
        XCTAssertEqual(output["style"] as? [String], CustomWidgetOutput.styles)
        XCTAssertEqual(output["tint"] as? [String], CustomWidgetOutput.tints)
        let preview = try NativeAgentHelp.render(command: "widget.preview", json: false)
        for field in ["style", "tint", "symbol", "apps"] { XCTAssertTrue(preview.contains(field), field) }
    }

    func testAgentEditsAreValidatedAndRevisionProtected() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("agent-test-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = DockStore(fileURL: url)
        let commands = NativeAgentCommands(store: store, visible: { _ in false }, setVisible: { _, _ in })
        func send(_ op: String, _ params: [String: Any] = [:], dryRun: Bool = false, revision: String? = nil) async throws -> [String: Any] {
            var request: [String: Any] = ["op": op, "params": params, "dryRun": dryRun]
            request["ifRevision"] = revision
            let data = await commands.handle(try JSONSerialization.data(withJSONObject: request))
            return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        }
        let before = try await send("state")
        let revision = try XCTUnwrap(before["revision"] as? String)
        let original = try store.exportData()
        let params: [String: Any] = ["dockID": store.active.id.uuidString, "kind": "custom", "patch": ["title": "Agent counter", "custom": ["actions": [["title": "Add", "script": "state.count += 1; return state;"]]]]]
        let dry = try await send("widget.add", params, dryRun: true)
        XCTAssertEqual(dry["ok"] as? Bool, true)
        XCTAssertEqual(try store.exportData(), original)
        let added = try await send("widget.add", params, revision: revision)
        XCTAssertEqual(added["ok"] as? Bool, true)
        let item = try XCTUnwrap(store.active.items.last)
        XCTAssertEqual(item.title, "Agent counter")
        XCTAssertEqual(item.custom?.actions.count, 1)
        let conflict = try await send("widget.remove", ["itemID": item.id.uuidString], revision: revision)
        XCTAssertEqual(conflict["ok"] as? Bool, false)
        XCTAssertTrue(store.active.items.contains { $0.id == item.id })
        let after = try store.exportData()
        let invalid = try await send("dock.update", ["dockID": store.active.id.uuidString, "patch": ["appearance": ["size": 500]]])
        XCTAssertEqual(invalid["ok"] as? Bool, false)
        XCTAssertEqual(try store.exportData(), after)
        let typo = try await send("widget.update", ["itemID": item.id.uuidString, "patch": ["custom": ["renderScrip": "oops"]]])
        XCTAssertEqual(typo["ok"] as? Bool, false)
        XCTAssertEqual(try store.exportData(), after)
        let updated = try await send("widget.update", ["itemID": item.id.uuidString, "patch": ["custom": ["state": ["count": 4]]]])
        XCTAssertEqual(updated["ok"] as? Bool, true)
        XCTAssertEqual(store.active.items.last?.custom?.state["count"], 4)
        let restored = DockStore(fileURL: url)
        XCTAssertEqual(restored.active.items.last?.custom?.state["count"], 4)
    }
}
#endif
