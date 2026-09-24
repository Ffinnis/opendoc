#if os(macOS)
import AppKit
import IOKit.ps

/// Shared measurements, type and colour for the dock, its widgets and their
/// cards, so every surface uses the same corners, fonts and feedback.
enum NativeDockStyle {
    /// Distance from the shelf's edge to the tiles inside it.
    static let shelfInset: CGFloat = 6
    /// Space after the last tile for the settings button and trailing padding.
    static let trailingLength: CGFloat = 30
    static let settingsButtonWidth: CGFloat = 20
    /// The settings button stays faintly visible so the end of the shelf reads
    /// as a control rather than empty space.
    static let restingChromeAlpha: CGFloat = 0.3
    /// Gap between an item and its hover label, on every edge and while magnified.
    static let labelGap: CGFloat = 8

    /// Pressed icons shrink and dim slightly, the same way at rest and magnified.
    static let pressScale: CGFloat = 0.94
    static let widgetPressScale: CGFloat = 0.985
    static let pressAlpha: CGFloat = 0.8

    /// App icons use Apple's icon corner ratio; widget and folder tiles match.
    static func tileRadius(iconSize: CGFloat) -> CGFloat { (iconSize * 0.2237).rounded() }

    /// Concentric with the tiles: the shelf corner is the tile corner plus the inset.
    static func shelfRadius(iconSize: CGFloat, thickness: CGFloat) -> CGFloat {
        min(thickness / 2, tileRadius(iconSize: iconSize) + shelfInset)
    }

    /// Glass tint. Graphite keeps the original darkening; colours are softened
    /// so the shelf stays calm behind its icons.
    static func tint(named name: String, strength: Double) -> NSColor? {
        guard strength > 0 else { return nil }
        let base: NSColor
        switch name {
        case "Accent": base = .controlAccentColor
        case "Blue": base = .systemBlue
        case "Purple": base = .systemPurple
        case "Pink": base = .systemPink
        case "Red": base = .systemRed
        case "Orange": base = .systemOrange
        case "Yellow": base = .systemYellow
        case "Green": base = .systemGreen
        default: return NSColor.black.withAlphaComponent(strength * 0.6)
        }
        return base.withAlphaComponent(strength * 0.5)
    }

    static func swatch(named name: String) -> NSColor {
        name == "Graphite" ? .systemGray : tint(named: name, strength: 1)?.withAlphaComponent(1) ?? .systemGray
    }

    /// Rounded numerals with fixed-width digits, so ticking values do not jitter.
    static func valueFont(_ size: CGFloat, weight: NSFont.Weight = .semibold) -> NSFont {
        let base = NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        guard let rounded = base.fontDescriptor.withDesign(.rounded) else { return base }
        return NSFont(descriptor: rounded, size: size) ?? base
    }

    /// Recessed tile surface: a faint fill with a light rim, instead of a box.
    static func tileFill(dark: Bool) -> NSColor {
        dark ? NSColor.white.withAlphaComponent(0.07) : NSColor.black.withAlphaComponent(0.05)
    }
    static func tileRim(dark: Bool) -> NSColor {
        dark ? NSColor.white.withAlphaComponent(0.1) : NSColor.white.withAlphaComponent(0.55)
    }
    /// A sticky note stays warm in both appearances.
    static func noteFill(dark: Bool) -> NSColor {
        dark ? NSColor(calibratedRed: 0.55, green: 0.45, blue: 0.14, alpha: 0.55)
            : NSColor(calibratedRed: 1, green: 0.87, blue: 0.4, alpha: 0.92)
    }
    static func noteText(dark: Bool) -> NSColor {
        dark ? NSColor(calibratedRed: 1, green: 0.95, blue: 0.8, alpha: 1) : NSColor(calibratedWhite: 0.12, alpha: 1)
    }
}

/// Colours and icons a custom widget's display function can ask for.
@MainActor
enum NativeWidgetPresentation {
    private static var icons: [String: NSImage?] = [:]

    static func color(_ tint: String?, progress: Double?, fallback: NSColor) -> NSColor {
        switch tint {
        case "level":
            // Without a current reading, such as after a failed refresh, the
            // level is unknown; do not show a reassuring green.
            guard let progress else { return fallback }
            return progress >= 0.5 ? .systemGreen : progress >= 0.2 ? .systemYellow : .systemRed
        case "blue": return .systemBlue
        case "purple": return .systemPurple
        case "pink": return .systemPink
        case "red": return .systemRed
        case "orange": return .systemOrange
        case "yellow": return .systemYellow
        case "green": return .systemGreen
        case "teal": return .systemTeal
        case "indigo": return .systemIndigo
        case "gray": return .systemGray
        default: return fallback
        }
    }

    /// The icon of the first available app among `bundleIDs`. Claude can also
    /// use the provider logo from an installed CodexBar when Claude Desktop is
    /// absent. Looked up once per identifier; neither app is launched.
    static func appIcon(_ bundleIDs: [String]?) -> NSImage? {
        for id in bundleIDs ?? [] {
            if let cached = icons[id] { if let cached { return cached } else { continue } }
            let icon = loadAppIcon(id) { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
            icons[id] = .some(icon)
            if let icon { return icon }
        }
        return nil
    }

    static func loadAppIcon(_ bundleID: String, applicationURL: (String) -> URL?) -> NSImage? {
        if let app = applicationURL(bundleID) { return NSWorkspace.shared.icon(forFile: app.path) }
        guard bundleID == "com.anthropic.claudefordesktop",
              let helper = applicationURL("com.steipete.codexbar") else { return nil }
        // Read the installed helper's own logo; do not redistribute another
        // app's artwork or let widget output supply arbitrary file paths.
        let logo = helper.appendingPathComponent("Contents/Resources/ProviderIcon-claude.svg")
        return NSImage(contentsOf: logo)
    }
}

extension WidgetKind {
    /// Each widget has one colour, used for its glyph, ring or bar and its card.
    var accent: NSColor {
        switch self {
        case .clock: .systemBlue
        case .worldClock: .systemIndigo
        case .calendar: .systemRed
        case .focus: .systemOrange
        case .stopwatch: .systemYellow
        case .countdown: .systemPurple
        case .reminders: .systemGreen
        case .hydration: .systemCyan
        case .battery: .systemGreen
        case .cpu: .systemBlue
        case .memory: .systemPurple
        case .webValue: .systemTeal
        case .custom: .controlAccentColor
        case .note: .systemYellow
        }
    }
}

/// Text shown by widgets in the dock and in their cards.
enum NativeWidgetFormat {
    /// Minutes and seconds, with hours once the value reaches an hour.
    static func clock(_ seconds: TimeInterval) -> String {
        let value = Int(min(315_360_000, max(0, seconds)))
        let hours = value / 3600, minutes = (value % 3600) / 60, rest = value % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%02d:%02d", minutes, rest)
    }

    /// Days and hours for long countdowns, otherwise a clock.
    static func countdown(_ seconds: TimeInterval) -> String {
        let value = Int(max(0, seconds))
        if value >= 86400 { return "\(value / 86400)d \((value % 86400) / 3600)h" }
        return clock(TimeInterval(value))
    }

    static func tasks(open: Int, total: Int) -> String {
        if total == 0 { return "No tasks" }
        if open == 0 { return "All done" }
        return open == 1 ? "1 task" : "\(open) tasks"
    }

    /// The time in another zone, in the user's 12- or 24-hour preference.
    static func time(in zone: String, at date: Date = Date(), seconds: Bool = false) -> String {
        var style = seconds ? Date.FormatStyle(date: .omitted, time: .standard) : Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = TimeZone(identifier: zone) ?? .current
        return date.formatted(style)
    }

    static func city(_ zone: String) -> String {
        zone.split(separator: "/").last?.replacingOccurrences(of: "_", with: " ") ?? "World clock"
    }

    /// A leading percentage in a reading such as "42%" or "42.5% used".
    static func fraction(from value: String) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard let end = trimmed.firstIndex(of: "%"), let number = Double(trimmed[..<end]) else { return nil }
        return min(1, max(0, number / 100))
    }
}

enum NativeBattery {
    struct Status: Equatable { var percentage: Int; var charging: Bool }

    static var status: Status? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let data = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  let current = data[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = data[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            return Status(percentage: Int(Double(current) / Double(maximum) * 100), charging: data[kIOPSIsChargingKey] as? Bool == true)
        }
        return nil
    }

    static var percentage: Int? { status?.percentage }

    static func symbol(for status: Status?) -> String {
        guard let status else { return "battery.0percent" }
        if status.charging { return "battery.100percent.bolt" }
        switch status.percentage {
        case 88...: return "battery.100percent"
        case 63...: return "battery.75percent"
        case 38...: return "battery.50percent"
        case 13...: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    static func color(for status: Status?) -> NSColor {
        guard let status, !status.charging else { return .systemGreen }
        return status.percentage <= 10 ? .systemRed : status.percentage <= 20 ? .systemYellow : .systemGreen
    }
}
#endif
