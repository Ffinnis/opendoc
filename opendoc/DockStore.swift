import Foundation

enum WidgetKind: String, Codable, CaseIterable {
    case clock, calendar, focus, note, reminders, hydration, stopwatch, countdown, battery, worldClock, custom, cpu, memory, webValue

    var title: String {
        switch self {
        case .clock: "Clock"
        case .calendar: "Calendar"
        case .focus: "Focus timer"
        case .note: "Sticky note"
        case .reminders: "Checklist"
        case .hydration: "Hydration"
        case .stopwatch: "Stopwatch"
        case .countdown: "Countdown"
        case .battery: "Battery"
        case .worldClock: "World clock"
        case .cpu: "CPU"
        case .memory: "Memory"
        case .webValue: "Web value"
        case .custom: "Custom widget"
        }
    }

    var symbol: String {
        switch self {
        case .clock: "clock"
        case .calendar: "calendar"
        case .focus: "timer"
        case .note: "note.text"
        case .reminders: "checklist"
        case .hydration: "drop"
        case .stopwatch: "stopwatch"
        case .countdown: "hourglass"
        case .battery: "battery.100percent"
        case .worldClock: "globe.europe.africa"
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .webValue: "network"
        case .custom: "square.stack.3d.up"
        }
    }

    var detail: String {
        switch self {
        case .clock: "Local time, updated every second."
        case .calendar: "Today's date and a monthly calendar."
        case .focus: "A configurable focus timer with pause and reset."
        case .note: "A note you can read directly in the dock."
        case .reminders: "A local checklist with a remaining task count."
        case .hydration: "Track glasses of water. Resets each day."
        case .stopwatch: "Measure elapsed time, even with the editor closed."
        case .countdown: "Count down to a date and time you choose."
        case .battery: "Current charge reported by your device."
        case .worldClock: "Time in any supported time zone."
        case .custom: "Interactive counters, webpage values, and your own button actions."
        case .cpu: "Live processor usage across all CPU cores."
        case .memory: "Active, wired, and compressed memory usage."
        case .webValue: "Display a value from your own HTTPS JSON endpoint."
        }
    }

    var category: String {
        switch self {
        case .focus, .note, .reminders: "Productivity"
        case .clock, .calendar, .worldClock, .stopwatch, .countdown: "Time"
        case .hydration, .custom: "Everyday"
        case .cpu, .memory, .battery: "System"
        case .webValue: "Custom data"
        }
    }
}

struct ChecklistItem: Codable, Identifiable {
    var id = UUID()
    var text: String
    var done = false
}

struct DockItem: Codable, Identifiable {
    enum Kind: String, Codable { case link, widget, spacer, file, application, trash, folder }
    var id = UUID()
    var kind: Kind
    var title: String
    var symbol: String
    var color = "blue"
    var url: String?
    var bookmark: Data?
    var widget: WidgetKind?
    var note = "Make something worth making."
    var checklist: [ChecklistItem] = []
    var count = 0
    var countDay = ""
    var timeZone = "Europe/London"
    var duration: TimeInterval = 25 * 60
    var remaining: TimeInterval = 25 * 60
    var startedAt: Date?
    var deadline: Date?
    var children: [DockItem]?
    var web: WebWidgetConfiguration?
    var custom: CustomWidgetConfiguration?

    static func widget(_ kind: WidgetKind) -> DockItem {
        var item = DockItem(kind: .widget, title: kind.title, symbol: kind.symbol, color: "green", widget: kind)
        if kind == .stopwatch { item.remaining = 0 }
        if kind == .countdown { item.deadline = Date().addingTimeInterval(86400) }
        if kind == .custom {
            #if os(macOS)
            item.custom = CustomWidgetConfiguration()
            #else
            item.note = "Your text here"
            #endif
        }
        return item
    }

    var containedItems: [DockItem] { [self] + (children ?? []) }

    func independentCopy() -> DockItem {
        var copy = self
        copy.id = UUID()
        copy.startedAt = nil
        copy.children = children?.map { $0.independentCopy() }
        return copy
    }

    func timerValue(at date: Date = Date()) -> TimeInterval {
        guard let startedAt else { return remaining }
        let elapsed = max(0, date.timeIntervalSince(startedAt))
        return widget == .stopwatch ? min(315_360_000, remaining + elapsed) : max(0, remaining - elapsed)
    }

    var dailyCount: Int { countDay == Self.dayKey() ? count : 0 }

    static func dayKey() -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }
}

struct DockAppearance: Codable {
    var position = "Bottom"
    var material = "Glass"
    var wallpaper = "Meadow"
    var size: Double = 60
    var autoHide = true
    var showLabels = true
    var glassStyle = "Regular"
    var glassTint: Double = 0

    init() {}
    enum CodingKeys: String, CodingKey {
        case position, material, wallpaper, size, autoHide, showLabels, glassStyle, glassTint
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        position = try values.decode(String.self, forKey: .position)
        material = try values.decode(String.self, forKey: .material)
        wallpaper = try values.decode(String.self, forKey: .wallpaper)
        size = try values.decode(Double.self, forKey: .size)
        autoHide = try values.decode(Bool.self, forKey: .autoHide)
        showLabels = try values.decode(Bool.self, forKey: .showLabels)
        glassStyle = try values.decodeIfPresent(String.self, forKey: .glassStyle) ?? "Regular"
        glassTint = try values.decodeIfPresent(Double.self, forKey: .glassTint) ?? 0
    }
}

struct DockProfile: Codable, Identifiable {
    var id = UUID()
    var name: String
    var symbol: String
    var color: String
    var items: [DockItem]
    var appearance = DockAppearance()
}

struct DockArchive: Codable {
    var version = 1
    var profiles: [DockProfile]
    var activeID: UUID

    func validate() throws {
        guard version == 1, !profiles.isEmpty, profiles.count <= 100,
              Set(profiles.map(\.id)).count == profiles.count,
              profiles.contains(where: { $0.id == activeID }) else { throw StoreError.invalidArchive }
        var itemIDs = Set<UUID>()
        for profile in profiles {
            guard !profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  profile.items.count <= 200, (36...88).contains(profile.appearance.size),
                  ["Left", "Bottom", "Right"].contains(profile.appearance.position),
                  ["Glass", "Light", "Dark"].contains(profile.appearance.material),
                  ["Clear", "Regular"].contains(profile.appearance.glassStyle),
                  (0...1).contains(profile.appearance.glassTint),
                  ["Meadow", "Dusk", "Ocean"].contains(profile.appearance.wallpaper) else { throw StoreError.invalidArchive }
            guard profile.items.allSatisfy({ item in
                if item.kind == .folder {
                    return item.children != nil && (item.children?.count ?? 0) <= 100
                        && (item.children ?? []).allSatisfy { $0.kind == .application && $0.children == nil }
                }
                return item.children == nil
            }) else { throw StoreError.invalidArchive }
            for item in profile.items.flatMap(\.containedItems) {
                guard itemIDs.insert(item.id).inserted, !item.title.isEmpty,
                      item.duration.isFinite, (1...315_360_000).contains(item.duration),
                      item.remaining.isFinite, (0...315_360_000).contains(item.remaining),
                      item.count >= 0, item.count <= 1000,
                      TimeZone(identifier: item.timeZone) != nil else { throw StoreError.invalidArchive }
                for date in [item.startedAt, item.deadline].compactMap({ $0 }) {
                    guard date >= Date.distantPast && date <= Date.distantFuture else { throw StoreError.invalidArchive }
                }
                if let web = item.web { try web.validate() }
                if let custom = item.custom { try custom.validate() }
                switch item.kind {
                case .widget: guard item.widget != nil else { throw StoreError.invalidArchive }
                case .link: guard let url = item.url, Self.allowedURL(url) != nil else { throw StoreError.invalidArchive }
                case .file: guard item.bookmark != nil else { throw StoreError.invalidArchive }
                case .spacer: break
                case .application:
                    guard let address = item.url, let url = URL(string: address), url.isFileURL,
                          url.pathExtension == "app" else { throw StoreError.invalidArchive }
                case .trash, .folder: break
                }
            }
        }
    }

    static func allowedURL(_ string: String) -> URL? {
        guard let url = URL(string: string), let scheme = url.scheme?.lowercased(),
              ["https", "http", "mailto", "shortcuts", "calshow", "music"].contains(scheme) else { return nil }
        if ["https", "http"].contains(scheme), url.host?.isEmpty != false { return nil }
        return url
    }
}

enum StoreError: LocalizedError {
    case invalidArchive, lastProfile, invalidName
    var errorDescription: String? {
        switch self {
        case .invalidArchive: "This isn't a valid Open Doc backup. Your current docks have not changed."
        case .lastProfile: "Keep at least one dock in your workspace."
        case .invalidName: "Give your dock a name."
        }
    }
}

@MainActor
final class DockStore {
    static let shared = DockStore()
    static let changed = Notification.Name("OpenDocStoreChanged")
    private(set) var archive: DockArchive
    private(set) var loadError: String?
    private let fileURL: URL
    let undoManager = UndoManager()

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenDoc/workspace.json")
        archive = Self.initialArchive()
        undoManager.levelsOfUndo = 30
        if FileManager.default.fileExists(atPath: self.fileURL.path) {
            do {
                let saved = try JSONDecoder().decode(DockArchive.self, from: Data(contentsOf: self.fileURL))
                try saved.validate()
                archive = saved
            } catch { loadError = "Your saved workspace could not be read. The original file is preserved. Export any new work before restarting. \(error.localizedDescription)" }
        }
    }

    var active: DockProfile { archive.profiles.first(where: { $0.id == archive.activeID }) ?? archive.profiles[0] }

    private func commit(_ next: DockArchive, recordUndo: Bool = true) throws {
        try next.validate()
        if loadError != nil { throw CocoaError(.fileReadCorruptFile) }
        let data = try encoded(next)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        if recordUndo {
            let previous = archive
            undoManager.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated { try? target.commit(previous) }
            }
            undoManager.setActionName("Dock Edit")
        }
        archive = next
        NotificationCenter.default.post(name: Self.changed, object: self)
    }

    func select(_ id: UUID) throws {
        var next = archive
        next.activeID = id
        try commit(next, recordUndo: false)
    }

    func update(_ profile: DockProfile) throws {
        guard let index = archive.profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        var next = archive
        next.profiles[index] = profile
        try commit(next)
    }

    func updateItem(_ item: DockItem) throws {
        guard var profile = archive.profiles.first(where: { $0.items.contains(where: { $0.id == item.id }) }) else { return }
        guard let index = profile.items.firstIndex(where: { $0.id == item.id }) else { return }
        profile.items[index] = item
        try update(profile)
    }

    func add(_ item: DockItem) throws {
        try add(item, to: active.id)
    }

    func add(_ item: DockItem, to profileID: UUID) throws {
        guard var profile = archive.profiles.first(where: { $0.id == profileID }) else { return }
        profile.items.append(item)
        try update(profile)
    }

    func create(name: String, duplicate: Bool = false) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw StoreError.invalidName }
        var profile = duplicate ? active : DockProfile(name: name, symbol: "square.grid.2x2", color: "green", items: [])
        profile.id = UUID()
        profile.name = name
        profile.items = profile.items.map { $0.independentCopy() }
        try create(profile)
    }

    func create(_ profile: DockProfile) throws {
        var next = archive
        next.profiles.append(profile)
        next.activeID = profile.id
        try commit(next)
    }

    func deleteActive() throws {
        guard archive.profiles.count > 1 else { throw StoreError.lastProfile }
        var next = archive
        next.profiles.removeAll { $0.id == next.activeID }
        next.activeID = next.profiles[0].id
        try commit(next)
    }

    func exportData() throws -> Data { try encoded(archive) }

    func importData(_ data: Data) throws {
        guard data.count <= 10_000_000 else { throw StoreError.invalidArchive }
        let imported = try JSONDecoder().decode(DockArchive.self, from: data)
        try imported.validate()
        var next = archive
        // Import copies. Existing profiles and their active selection are preserved.
        for var profile in imported.profiles {
            profile.id = UUID()
            profile.name += " (imported)"
            profile.items = profile.items.map { $0.independentCopy() }
            next.profiles.append(profile)
        }
        try commit(next)
    }

    private func encoded(_ archive: DockArchive) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(archive)
    }

    static func initialArchive() -> DockArchive {
        let browser = DockItem(kind: .link, title: "Browser", symbol: "safari.fill", color: "blue", url: "https://www.apple.com")
        let github = DockItem(kind: .link, title: "GitHub", symbol: "chevron.left.forwardslash.chevron.right", color: "ink", url: "https://github.com")
        let mail = DockItem(kind: .link, title: "Mail", symbol: "envelope.fill", color: "blue", url: "mailto:")
        let spacer = DockItem(kind: .spacer, title: "Spacer", symbol: "line.3.vertical", color: "gray")
        let work = DockProfile(name: "Everyday", symbol: "sun.max", color: "green", items: [browser, mail, github, spacer, .widget(.clock), .widget(.focus), .widget(.note)])
        var personal = DockProfile(name: "Personal", symbol: "house", color: "orange", items: [.widget(.calendar), .widget(.hydration), .widget(.worldClock)])
        personal.appearance.wallpaper = "Dusk"
        var focus = DockProfile(name: "Deep work", symbol: "moon", color: "purple", items: [.widget(.focus), .widget(.reminders), .widget(.note)])
        focus.appearance.wallpaper = "Ocean"
        return DockArchive(profiles: [work, personal, focus], activeID: work.id)
    }
}
