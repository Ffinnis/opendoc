#if os(macOS)
import XCTest
@testable import opendoc

@MainActor
final class WidgetCommandTests: XCTestCase {
    private func shell(_ script: String, timeout: TimeInterval = 2) -> WidgetCommandConfiguration {
        var command = WidgetCommandConfiguration()
        command.enabled = true; command.executable = "/bin/bash"
        command.arguments = ["-c", script]; command.timeout = timeout
        return command
    }

    private func expectFailure(_ command: WidgetCommandConfiguration, containing text: String) async {
        do { _ = try await NativeWidgetCommand.run(command); XCTFail("Command unexpectedly succeeded") }
        catch { XCTAssertTrue(error.localizedDescription.contains(text), error.localizedDescription) }
    }

    func testLegacyConfigurationAndTemplatesDoNotEnableCommands() throws {
        let original = CustomWidgetConfiguration.water()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json.removeValue(forKey: "command")
        let restored = try JSONDecoder().decode(CustomWidgetConfiguration.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(restored, original)
        for config in [CustomWidgetConfiguration.commandTemplate(), .codexBar(provider: "codex"), .codexBar(provider: "claude")] {
            XCTAssertFalse(config.command.enabled)
            XCTAssertNoThrow(try config.validate())
        }
    }

    func testArgumentsAreLiteralAndStderrIsSeparate() async throws {
        var command = shell("")
        command.executable = "/usr/bin/printf"
        command.arguments = ["%s", #"{"value":"$(touch /never-run); `id` $HOME"}"#]
        let input = try await NativeWidgetCommand.run(command)
        XCTAssertEqual(input.text, command.arguments[1])
        let separate = try await NativeWidgetCommand.run(shell("printf 'diagnostic' >&2; printf '{\"value\":42}'"))
        XCTAssertEqual(separate.text, #"{"value":42}"#)
    }

    func testDisabledInvalidFailedAndOversizedCommands() async {
        var disabled = shell("exit 99"); disabled.enabled = false
        await expectFailure(disabled, containing: "Enable local command")
        await expectFailure(shell("exit 7"), containing: "exit code 7")
        await expectFailure(shell("printf 'not json'"), containing: "one UTF-8 JSON")
        await expectFailure(shell("/usr/bin/yes x"), containing: "64 KB")
        var missing = shell(""); missing.executable = "/does-not-exist/opendoc-widget"
        await expectFailure(missing, containing: "Could not start")
    }

    func testTimeoutStopsChildProcessesAndClosedOutputCannotHang() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("widget-child-\(UUID())")
        defer { try? FileManager.default.removeItem(at: file) }
        let start = Date()
        await expectFailure(shell("sleep 30 & echo $! > '\(file.path)'; wait", timeout: 1), containing: "timeout")
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
        let pid = try XCTUnwrap(Int32(String(contentsOf: file, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        // Allow launchd to reap the killed orphan before checking its existence.
        for _ in 0..<50 where kill(pid, 0) == 0 { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(kill(pid, 0), -1)
        await expectFailure(shell("exec 1>&-; sleep 30", timeout: 1), containing: "timeout")
    }

    func testCommandPreviewAndCodexBarWindowFallback() async throws {
        var config = CustomWidgetConfiguration.commandTemplate()
        config.command.enabled = true
        let output = try await NativeCustomWidgetData.shared.preview(config)
        XCTAssertEqual(output, CustomWidgetOutput(value: "Hello", detail: "Command widget"))
        let template = CustomWidgetConfiguration.codexBar(provider: "codex")
        let input = CustomWidgetInput(text: #"[{"provider":"codex","usage":{"primary":null,"secondary":{"usedPercent":11,"windowMinutes":10080}}}]"#)
        let result = try NativeCustomScript.evaluate(.init(script: template.renderScript, state: [:], input: input, action: false))
        XCTAssertEqual(result.output?.value, "89% left")
        XCTAssertEqual(result.output?.detail, "Codex · Weekly")
        XCTAssertEqual(result.output?.progress, 0.89)
        XCTAssertEqual(result.output?.style, "ring")
        XCTAssertEqual(result.output?.tint, "level")
        XCTAssertEqual(result.output?.apps, ["com.openai.codex", "com.openai.chat"])
        XCTAssertEqual(result.output?.symbol, "chevron.left.forwardslash.chevron.right")
        XCTAssertThrowsError(try NativeCustomScript.evaluate(.init(script: template.renderScript, state: [:], input: .init(text: #"[{"provider":"codex","usage":{}}]"#), action: false)))
    }

    func testRenderPresentationFieldsAreValidated() throws {
        func render(_ script: String) throws -> CustomWidgetOutput? {
            try NativeCustomScript.evaluate(.init(script: script, state: [:], input: .init(), action: false)).output
        }
        let output = try render("return { value: '40%', progress: 0.4, style: 'ring', tint: 'level', symbol: 'drop.fill', apps: ['com.apple.Safari'] };")
        XCTAssertEqual(output, CustomWidgetOutput(value: "40%", progress: 0.4, style: "ring", tint: "level", symbol: "drop.fill", apps: ["com.apple.Safari"]))
        XCTAssertEqual(try render("return { value: 1, style: null, tint: null };"), CustomWidgetOutput(value: "1"), "Presentation stays optional")
        // Unsupported values are ignored so command JSON that reuses these names keeps rendering.
        for script in [
            "return { value: 1, style: 'donut' };",
            "return { value: 1, tint: '#ff0000' };",
            "return { value: 1, symbol: 'BRK-B' };",
            "return { value: 1, symbol: 3 };",
            "return { value: 1, apps: 'com.apple.Safari' };",
            "return { value: 1, apps: [] };",
            "return { value: 1, apps: ['/Applications/Safari.app'] };"
        ] {
            XCTAssertEqual(try render(script), CustomWidgetOutput(value: "1"), script)
        }
        XCTAssertEqual(try render("return { value: 1, apps: ['a.b', 'bad id', 'c.d', 'e.f', 'g.h', 'i.j'] };")?.apps, ["a.b", "c.d", "e.f"],
                       "At most four entries are read and invalid ones are skipped")
    }

    func testOutputWithoutPresentationStillDecodes() throws {
        let decoded = try JSONDecoder().decode(CustomWidgetOutput.self, from: Data(#"{"value":"3","detail":"Today","progress":0.5}"#.utf8))
        XCTAssertEqual(decoded, CustomWidgetOutput(value: "3", detail: "Today", progress: 0.5))
    }

    func testRefreshKeepsLastValueAfterCommandFailure() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("widget-value-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data(#"{"value":"42%","detail":"Quota","progress":0.42}"#.utf8).write(to: file)
        var config = CustomWidgetConfiguration.commandTemplate()
        config.command.enabled = true; config.command.executable = "/bin/cat"; config.command.arguments = [file.path]
        var item = DockItem.widget(.custom); item.custom = config
        let service = NativeCustomWidgetData()
        for _ in 0..<100 {
            if service.reading(for: item).output.value == "42%" { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(service.reading(for: item).output.value, "42%")
        try FileManager.default.removeItem(at: file)
        // Cached reads must not execute the command again before refresh.
        XCTAssertFalse(service.reading(for: item).isError)
        service.refresh(item)
        for _ in 0..<100 {
            if service.reading(for: item).isError { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(service.reading(for: item).isError)
        XCTAssertEqual(service.reading(for: item).output.value, "42%")
    }

    func testAgentCommandValidationAndDryRunNeverExecute() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("command-agent-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let marker = directory.appendingPathComponent("executed")
        let store = DockStore(fileURL: directory.appendingPathComponent("workspace.json"))
        let targetID = store.active.id
        try store.create(name: "Other selected dock")
        let commands = NativeAgentCommands(store: store, visible: { _ in false }, setVisible: { _, _ in })
        func send(_ op: String, _ params: [String: Any], dryRun: Bool = false) async throws -> [String: Any] {
            let data = try JSONSerialization.data(withJSONObject: ["op": op, "params": params, "dryRun": dryRun])
            let response = await commands.handle(data)
            return try XCTUnwrap(JSONSerialization.jsonObject(with: response) as? [String: Any])
        }
        let before = try store.exportData()
        let command: [String: Any] = ["enabled": true, "executable": "/bin/bash", "arguments": ["-c", "touch '\(marker.path)'; printf '{}'"], "timeout": 2]
        let params: [String: Any] = ["dockID": targetID.uuidString, "kind": "custom", "patch": ["custom": ["source": "command", "command": command]]]
        let dryRun = try await send("widget.add", params, dryRun: true)
        XCTAssertEqual(dryRun["ok"] as? Bool, true)
        XCTAssertEqual(try store.exportData(), before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
        let added = try await send("widget.add", params)
        XCTAssertEqual(added["ok"] as? Bool, true)
        let item = try XCTUnwrap(store.archive.profiles.first { $0.id == targetID }?.items.last)
        XCTAssertEqual(item.custom?.command.executable, "/bin/bash")
        XCTAssertFalse(store.active.items.contains { $0.id == item.id })
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
        let saved = try store.exportData()
        for patch: [String: Any] in [["executable": "bash"], ["timeout": 26], ["arguments": ["bad\0argument"]], ["unknown": true], ["enabled": "true"]] {
            let result = try await send("widget.update", ["itemID": item.id.uuidString, "patch": ["custom": ["command": patch]]])
            XCTAssertEqual(result["ok"] as? Bool, false)
            XCTAssertEqual(try store.exportData(), saved)
        }
        let restored = DockStore(fileURL: directory.appendingPathComponent("workspace.json"))
        XCTAssertEqual(restored.archive.profiles.first { $0.id == targetID }?.items.last?.custom, item.custom)
    }
}
#endif
