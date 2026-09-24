#if os(macOS)
import XCTest
@testable import opendoc

final class DockStyleTests: XCTestCase {
    @MainActor
    func testClaudeLogoUsesInstalledHelperWhenDesktopAppIsAbsent() throws {
        let helper = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("CodexBar.app")
        let resources = helper.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: helper.deletingLastPathComponent()) }
        // Original test artwork, not a redistributed provider logo.
        let svg = #"<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32"><rect width="32" height="32" fill="white"/></svg>"#
        let logo = resources.appendingPathComponent("ProviderIcon-claude.svg")
        try Data(svg.utf8).write(to: logo)
        var lookups: [String] = []
        let image = NativeWidgetPresentation.loadAppIcon("com.anthropic.claudefordesktop") { id in
            lookups.append(id)
            return id == "com.steipete.codexbar" ? helper : nil
        }
        XCTAssertNotNil(image)
        XCTAssertEqual(lookups, ["com.anthropic.claudefordesktop", "com.steipete.codexbar"])
        XCTAssertNil(NativeWidgetPresentation.loadAppIcon("com.example.missing") { _ in nil })
        try FileManager.default.removeItem(at: logo)
        XCTAssertNil(NativeWidgetPresentation.loadAppIcon("com.anthropic.claudefordesktop") { $0 == "com.steipete.codexbar" ? helper : nil })
    }

    @MainActor
    func testInstalledClaudeAppTakesPriorityOverHelperLogo() {
        var lookups: [String] = []
        let image = NativeWidgetPresentation.loadAppIcon("com.anthropic.claudefordesktop") { id in
            lookups.append(id)
            return URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
        }
        XCTAssertNotNil(image)
        XCTAssertEqual(lookups, ["com.anthropic.claudefordesktop"])
    }

    func testTimersShowHoursPastSixtyMinutes() {
        XCTAssertEqual(NativeWidgetFormat.clock(0), "00:00")
        XCTAssertEqual(NativeWidgetFormat.clock(25 * 60), "25:00")
        XCTAssertEqual(NativeWidgetFormat.clock(59 * 60 + 59), "59:59")
        XCTAssertEqual(NativeWidgetFormat.clock(3600), "1:00:00")
        XCTAssertEqual(NativeWidgetFormat.clock(5 * 3600 + 62), "5:01:02")
        XCTAssertEqual(NativeWidgetFormat.clock(-5), "00:00")
    }

    func testCountdownUsesDaysThenClock() {
        XCTAssertEqual(NativeWidgetFormat.countdown(5 * 3600), "5:00:00", "Five hours must not read 300:00")
        XCTAssertEqual(NativeWidgetFormat.countdown(86400 + 3 * 3600 + 59), "1d 3h")
        XCTAssertEqual(NativeWidgetFormat.countdown(90), "01:30")
        XCTAssertEqual(NativeWidgetFormat.countdown(-10), "00:00")
    }

    func testTaskCountIsGrammatical() {
        XCTAssertEqual(NativeWidgetFormat.tasks(open: 1, total: 3), "1 task")
        XCTAssertEqual(NativeWidgetFormat.tasks(open: 2, total: 3), "2 tasks")
        XCTAssertEqual(NativeWidgetFormat.tasks(open: 0, total: 3), "All done")
        XCTAssertEqual(NativeWidgetFormat.tasks(open: 0, total: 0), "No tasks")
    }

    func testReadingFractionsAndCityNames() {
        XCTAssertEqual(NativeWidgetFormat.fraction(from: "42%"), 0.42)
        XCTAssertEqual(NativeWidgetFormat.fraction(from: " 12.5% used"), 0.125)
        XCTAssertEqual(NativeWidgetFormat.fraction(from: "150%"), 1)
        XCTAssertNil(NativeWidgetFormat.fraction(from: "…"))
        XCTAssertNil(NativeWidgetFormat.fraction(from: "3.2 GB"))
        XCTAssertEqual(NativeWidgetFormat.city("America/New_York"), "New York")
    }

    func testWorldClockUsesTheZoneAndLocalePreference() throws {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-01-15T12:00:00Z"))
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        XCTAssertEqual(NativeWidgetFormat.time(in: "Asia/Tokyo", at: date), date.formatted(style))
    }

    @MainActor
    func testRingDetailsBreakBetweenParts() {
        let font = NSFont.systemFont(ofSize: 10, weight: .medium)
        let width = ("Codex · Weekly" as NSString).size(withAttributes: [.font: font]).width + 1
        XCTAssertEqual(NativeDockItemView.detailLines("Codex · Weekly · 6d", width: width, font: font, maximum: 2), ["Codex · Weekly", "6d"])
        XCTAssertEqual(NativeDockItemView.detailLines("Codex · Weekly · 6d", width: 500, font: font, maximum: 2), ["Codex · Weekly · 6d"])
        XCTAssertEqual(NativeDockItemView.detailLines("A · B · C", width: 1, font: font, maximum: 2), ["A", "B · C"])
        XCTAssertEqual(NativeDockItemView.detailLines("", width: 100, font: font, maximum: 2), [])
    }

    @MainActor
    func testLevelTintNeedsAReading() {
        XCTAssertEqual(NativeWidgetPresentation.color("level", progress: 0.8, fallback: .systemBlue), .systemGreen)
        XCTAssertEqual(NativeWidgetPresentation.color("level", progress: 0.3, fallback: .systemBlue), .systemYellow)
        XCTAssertEqual(NativeWidgetPresentation.color("level", progress: 0.1, fallback: .systemBlue), .systemRed)
        XCTAssertEqual(NativeWidgetPresentation.color("level", progress: nil, fallback: .systemBlue), .systemBlue, "A failed reading is not green")
        XCTAssertEqual(NativeWidgetPresentation.color(nil, progress: 0.9, fallback: .systemBlue), .systemBlue)
    }

    @MainActor
    func testPreviewTilesOfHiddenDocksNeverRunWidgets() {
        var item = DockItem.widget(.custom)
        var config = CustomWidgetConfiguration.commandTemplate()
        config.command.enabled = true
        item.custom = config
        let tile = NativeDockItemView(item: item, iconSize: 60, vertical: false, live: false)
        tile.refreshIfNeeded(at: Date().addingTimeInterval(5))
        XCTAssertFalse(NativeCustomWidgetData.shared.isTracking(item.id), "A preview must not run a command widget")
        tile.refreshIfNeeded(at: Date().addingTimeInterval(10))
        XCTAssertFalse(NativeCustomWidgetData.shared.isTracking(item.id), "Later refreshes stay idle too")
    }

    @MainActor
    func testHoverLabelShownDuringFadeOutStaysVisible() {
        let parent = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 300, height: 80), styleMask: [.borderless], backing: .buffered, defer: false)
        parent.orderFrontRegardless()
        defer { parent.orderOut(nil) }
        let label = NativeDockHoverLabel()
        let anchor = NSRect(x: 220, y: 210, width: 60, height: 60)
        let first = UUID(), second = UUID()
        label.show("Safari", itemID: first, anchor: anchor, edge: "Bottom", in: parent)
        label.hide()
        XCTAssertFalse(label.isShown, "Fading out counts as hidden")
        label.show("Mail", itemID: second, anchor: anchor.offsetBy(dx: 63, dy: 0), edge: "Bottom", in: parent)
        label.hide(); label.hide()
        label.show("Mail", itemID: second, anchor: anchor.offsetBy(dx: 63, dy: 0), edge: "Bottom", in: parent)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        XCTAssertTrue(label.isShown, "The earlier fade-out must not remove a label shown again")
        XCTAssertEqual(label.itemID, second)
        label.hide()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        XCTAssertFalse(label.isShown)
    }

    @MainActor
    func testShelfCornersAreConcentricWithTiles() {
        for size: CGFloat in [36, 44, 60, 88] {
            let thickness = size + 22
            XCTAssertEqual(NativeDockStyle.shelfRadius(iconSize: size, thickness: thickness),
                           NativeDockStyle.tileRadius(iconSize: size) + NativeDockStyle.shelfInset)
        }
        XCTAssertEqual(NativeDockStyle.shelfRadius(iconSize: 60, thickness: 20), 10, "Never rounder than a capsule")
    }

    @MainActor
    func testEveryTintColourHasAColourAndNoneWithoutStrength() {
        for name in DockAppearance.tintColors {
            XCTAssertNil(NativeDockStyle.tint(named: name, strength: 0), name)
            XCTAssertNotNil(NativeDockStyle.tint(named: name, strength: 0.5), name)
        }
        let graphite = NativeDockStyle.tint(named: "Graphite", strength: 1)?.usingColorSpace(.sRGB)
        XCTAssertEqual(graphite?.alphaComponent ?? 0, 0.6, accuracy: 0.001, "Graphite keeps the original darkening")
    }

    func testTintColourValidation() throws {
        var archive = DockArchive(profiles: [DockProfile(name: "Test", symbol: "dock.rectangle", color: "blue", items: [])], activeID: UUID())
        archive.activeID = archive.profiles[0].id
        archive.profiles[0].appearance.tintColor = "Pink"
        XCTAssertNoThrow(try archive.validate())
        archive.profiles[0].appearance.tintColor = "Chartreuse"
        XCTAssertThrowsError(try archive.validate())
    }

    @MainActor
    func testDragSnapshotIncludesLayerArtwork() throws {
        var app = DockItem(kind: .application, title: "Finder", symbol: "app")
        app.url = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app").absoluteString
        let tile = NativeDockItemView(item: app, iconSize: 60, vertical: false)
        tile.frame = NSRect(x: 0, y: 0, width: 67, height: 70)
        tile.layoutSubtreeIfNeeded()
        let image = tile.snapshot()
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        // The icon's centre must be opaque: a display cache used to drop it.
        let center = try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2 - 3))
        XCTAssertGreaterThan(center.alphaComponent, 0.5)
    }
}
#endif
