#if os(macOS)
import AppKit

@MainActor
final class NativeCustomWidgetData {
    static let shared = NativeCustomWidgetData()
    struct Reading: Equatable {
        var output = CustomWidgetOutput(value: "…", detail: "Loading…")
        var status = ""
        var isError = false
    }
    private struct Entry {
        var configuration: CustomWidgetConfiguration
        var day: String
        var reading = Reading()
        var nextRefresh = Date.distantPast
        var loading = false
        var input = CustomWidgetInput()
    }
    private var cache: [UUID: Entry] = [:]
    private var requests = 0
    private var activeActions = Set<UUID>()
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12; config.timeoutIntervalForResource = 15
        config.httpCookieStorage = nil; config.urlCredentialStorage = nil
        return URLSession(configuration: config)
    }()

    /// Whether this widget has been read, which starts its script or command.
    func isTracking(_ itemID: UUID) -> Bool { cache[itemID] != nil }

    /// The last reading, without running the widget's script or command.
    func cachedReading(for item: DockItem) -> Reading? {
        guard let reading = cache[item.id]?.reading, reading.output.value != "…" else { return nil }
        return reading
    }

    func reading(for item: DockItem) -> Reading {
        guard let config = item.custom else { return Reading(output: CustomWidgetOutput(value: item.note, detail: item.title), status: "Choose a template to make this widget interactive.") }
        let day = DockItem.dayKey()
        if cache[item.id]?.configuration != config || (config.resetDaily && cache[item.id]?.day != day) {
            cache[item.id] = Entry(configuration: config, day: day)
        }
        guard let entry = cache[item.id] else { return Reading() }
        if !entry.loading && entry.nextRefresh <= Date() && requests < 2 {
            cache[item.id]?.loading = true; requests += 1
            Task { [weak self] in
                guard let self else { return }
                let reading: Reading
                var input = CustomWidgetInput()
                do {
                    input = try await sourceInput(config)
                    let output = try await render(config, input: input)
                    reading = Reading(output: output, status: config.source != .local ? "Updated \(Date().formatted(date: .omitted, time: .shortened))" : "Saved on this Mac")
                } catch {
                    reading = Reading(output: entry.reading.output.value == "…" ? CustomWidgetOutput(value: "Check widget", detail: "Configuration error") : entry.reading.output,
                                      status: error.localizedDescription, isError: true)
                }
                requests -= 1
                guard cache[item.id]?.configuration == config, cache[item.id]?.day == day else { return }
                cache[item.id]?.reading = reading; cache[item.id]?.input = input
                cache[item.id]?.loading = false
                cache[item.id]?.nextRefresh = config.source != .local ? Date().addingTimeInterval(config.refreshInterval) : .distantFuture
            }
        }
        return entry.reading
    }

    func refresh(_ item: DockItem) { cache[item.id]?.nextRefresh = .distantPast; _ = reading(for: item) }

    func preview(_ config: CustomWidgetConfiguration) async throws -> CustomWidgetOutput {
        try config.validate()
        let input = try await sourceInput(config)
        return try await render(config, input: input)
    }

    private func sourceInput(_ config: CustomWidgetConfiguration) async throws -> CustomWidgetInput {
        try config.validate()
        switch config.source {
        case .local: return CustomWidgetInput()
        case .webpage: return try await pageInput(config)
        case .command: return try await NativeWidgetCommand.run(config.command)
        }
    }

    private func render(_ config: CustomWidgetConfiguration, input: CustomWidgetInput) async throws -> CustomWidgetOutput {
        try config.validate()
        let response = try await NativeCustomScript.run(.init(script: config.renderScript, state: config.effectiveState(day: DockItem.dayKey()), input: input, action: false))
        guard let output = response.output else { throw CustomWidgetError.message("The script did not return a widget value.") }
        return output
    }

    func perform(actionID: UUID, itemID: UUID, store: DockStore) async throws {
        guard !activeActions.contains(itemID) else { return }
        guard let original = store.archive.profiles.flatMap(\.items).first(where: { $0.id == itemID }),
              let config = original.custom, let action = config.actions.first(where: { $0.id == actionID }) else { return }
        activeActions.insert(itemID)
        defer { activeActions.remove(itemID) }
        let input = cache[itemID]?.input ?? CustomWidgetInput()
        let response = try await NativeCustomScript.run(.init(script: action.script, state: config.effectiveState(day: DockItem.dayKey()), input: input, action: true))
        guard let state = response.state else {
            throw CustomWidgetError.message("The action must return the updated state.")
        }
        var updated = config
        updated.state = state; updated.stateDay = DockItem.dayKey()
        let output = try await render(updated, input: input)
        guard var current = store.archive.profiles.flatMap(\.items).first(where: { $0.id == itemID }), current.custom == config else {
            throw CustomWidgetError.message("The widget changed while this action was running. Try again.")
        }
        current.custom = updated
        try store.updateItem(current)
            cache[itemID] = Entry(configuration: updated, day: DockItem.dayKey(),
                                  reading: Reading(output: output, status: "Saved on this Mac"),
                                  nextRefresh: updated.source != .local ? Date().addingTimeInterval(updated.refreshInterval) : .distantFuture,
                                  input: input)
    }

    private func pageInput(_ config: CustomWidgetConfiguration) async throws -> CustomWidgetInput {
        try config.validate()
        var request = URLRequest(url: URL(string: config.endpoint)!)
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw CustomWidgetError.message("The webpage returned HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0).")
        }
        guard response.url?.scheme == "https" else { throw URLError(.secureConnectionFailed) }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 1_048_576 else { throw CustomWidgetError.message("The webpage exceeds the 1 MB HTML limit.") }
            data.append(byte)
        }
        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { throw CustomWidgetError.message("The webpage text could not be decoded.") }
        return try await NativePageExtractor().extract(html: html, selector: config.selector, attribute: config.attribute)
    }
}
#endif
