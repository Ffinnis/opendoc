#if os(macOS)
import AppKit
import XCTest
@testable import opendoc

@MainActor
final class NativeDockDragTests: XCTestCase {
    func testRunningAppsDeduplicateBundlePathsAndExcludeFolderChildren() {
        let a = URL(fileURLWithPath: "/Applications/A.app")
        let b = URL(fileURLWithPath: "/Applications/B.app")
        var folder = DockItem(kind: .folder, title: "Tools", symbol: "folder")
        folder.children = [NativeApplications.item(for: a)]
        XCTAssertEqual(NativeApplications.unpinnedURLs([a, b, URL(fileURLWithPath: "/Applications/../Applications/B.app"), a], in: [folder]), [b])
    }

    func testOpenFolderEditRefreshesMagnifiedArtworkAndRunningDot() throws {
        try XCTSkipIf(NativeMotion.reducesMotion, "Magnification is disabled by Reduce Motion.")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = DockStore(fileURL: url)
        var folder = DockItem(kind: .folder, title: "Running app", symbol: "folder")
        folder.children = [NativeApplications.item(for: Bundle.main.bundleURL)]
        var profile = DockProfile(name: "Folder refresh", symbol: "folder", color: "green", items: [folder])
        profile.appearance.autoHide = false
        try store.create(profile)
        let application = MacApplication()
        let controller = NativeDockController(profileID: profile.id, store: store, application: application)
        defer { controller.close() }
        controller.showWindow(nil)
        XCTAssertEqual(controller.window?.allowsToolTipsWhenApplicationIsInactive, true)
        controller.previewMagnification()
        let overlay = try XCTUnwrap(controller.window?.childWindows?.first, "Reduce Motion: \(NativeMotion.reducesMotion), screens: \(NSScreen.screens.map(\.frame)), dock: \(String(describing: controller.window?.frame))")
        XCTAssertTrue(overlay.allowsToolTipsWhenApplicationIsInactive)
        let artwork = try XCTUnwrap(overlay.contentView?.subviews.first { ($0.layer?.sublayers?.count ?? 0) >= 2 })
        let image = try XCTUnwrap(artwork.layer?.sublayers?.first)
        let dot = try XCTUnwrap(artwork.layer?.sublayers?.dropFirst().first)
        let oldContents = try XCTUnwrap(image.contents) as AnyObject
        if #available(macOS 26.0, *) {
            let glass = try XCTUnwrap(overlay.contentView?.subviews.compactMap { $0 as? NSGlassEffectView }.first { $0.contentView is NSImageView })
            XCTAssertNotNil((glass.contentView as? NSImageView)?.image)
            XCTAssertEqual(glass.frame, image.frame)
            XCTAssertFalse(glass.isHidden)
            XCTAssertEqual(glass.alphaValue, 1)
            XCTAssertTrue(image.isHidden, "The preview belongs inside native glass, without a duplicate layer above it")
        }
        XCTAssertFalse(dot.isHidden)
        let magnifier = try XCTUnwrap(overlay.windowController as? NativeDockMagnification)
        let visible = image.presentation()?.frame ?? image.frame
        magnifier.update(at: overlay.convertPoint(toScreen: NSPoint(x: visible.midX, y: visible.midY)), animated: false)
        let label = try XCTUnwrap(overlay.contentView?.subviews.compactMap { $0 as? NativeDockTooltip }.first)
        XCTAssertFalse(label.isHidden)
        XCTAssertEqual(label.title, folder.title)
        label.layoutSubtreeIfNeeded()
        let text = try XCTUnwrap(label.subviews.compactMap { $0 as? NSTextField }.first)
        XCTAssertEqual(text.frame.midY, label.bounds.midY, accuracy: 0.5)
        controller.open(folder)
        XCTAssertTrue(label.isHidden)
        folder.children = []
        try store.updateItem(folder)
        controller.reload()
        XCTAssertTrue(overlay.isVisible)
        XCTAssertFalse(overlay.childWindows?.isEmpty ?? true)
        XCTAssertFalse(oldContents === image.contents as AnyObject)
        XCTAssertTrue(dot.isHidden)
    }

    func testFolderRunningIndicatorIncludesItsApplications() throws {
        let url = try XCTUnwrap(NSWorkspace.shared.runningApplications.compactMap(\.bundleURL).first)
        let app = NativeApplications.item(for: url)
        var folder = DockItem(kind: .folder, title: "Running", symbol: "folder")
        folder.children = [app]
        XCTAssertTrue(NativeApplications.isRunning(app))
        XCTAssertTrue(NativeApplications.isRunning(folder))
        folder.children = []
        XCTAssertFalse(NativeApplications.isRunning(folder))
    }

    func testCancelledSideDragAppliesDeferredWidgetEdit() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = DockStore(fileURL: url)
        var clock = DockItem.widget(.clock)
        var profile = DockProfile(name: "Side drag", symbol: "clock", color: "green", items: [clock])
        profile.appearance.position = "Right"
        try store.create(profile)
        let application = MacApplication()
        let controller = NativeDockController(profileID: profile.id, store: store, application: application)
        defer { controller.close() }
        func findTile(in view: NSView) -> NativeDockItemView? {
            (view as? NativeDockItemView) ?? view.subviews.compactMap { findTile(in: $0) }.first
        }
        let source = try XCTUnwrap(findTile(in: XCTUnwrap(controller.window?.contentView)))
        controller.beginDrag(source)
        clock.title = "Updated while dragging"
        try store.updateItem(clock)
        controller.reload()
        XCTAssertNotEqual(source.item.title, clock.title)
        controller.finishDrag(at: NSPoint(x: -10000, y: -10000))
        XCTAssertEqual(source.item.title, clock.title)
        XCTAssertFalse(controller.interacting)
    }

    func testFolderDragKeepsOverlayUntilReleaseAndCommitsOrder() throws {
        try XCTSkipIf(NativeMotion.reducesMotion, "Magnification is disabled by Reduce Motion.")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = DockStore(fileURL: url)
        var folder = DockItem(kind: .folder, title: "Tools", symbol: "folder")
        folder.children = []
        let clock = DockItem.widget(.clock)
        var profile = DockProfile(name: "Drag regression", symbol: "folder", color: "green", items: [folder, clock])
        profile.appearance.autoHide = false
        try store.create(profile)
        let application = MacApplication()
        let controller = NativeDockController(profileID: profile.id, store: store, application: application)
        defer { controller.close() }
        controller.showWindow(nil)
        let panel = try XCTUnwrap(controller.window)
        let root = try XCTUnwrap(panel.contentView)
        func tiles(in view: NSView) -> [NativeDockItemView] {
            if let tile = view as? NativeDockItemView { return [tile] }
            return view.subviews.flatMap { tiles(in: $0) }
        }
        let views = tiles(in: root)
        let source = try XCTUnwrap(views.first { $0.item.id == folder.id })
        let target = try XCTUnwrap(views.first { $0.item.id == clock.id })
        controller.previewMagnification()
        let overlay = try XCTUnwrap(panel.childWindows?.first, "Reduce Motion: \(NativeMotion.reducesMotion), screens: \(NSScreen.screens.map(\.frame)), dock: \(panel.frame)")
        controller.beginDrag(source)
        controller.reload() // A concurrent workspace notification must not end the drag.
        controller.updatePointer()
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        XCTAssertTrue(controller.interacting)
        XCTAssertTrue(overlay.isVisible)
        XCTAssertTrue(panel.childWindows?.contains { $0 === overlay } == true)
        let drop = target.convert(NSPoint(x: target.bounds.maxX - 2, y: target.bounds.midY), to: nil)
        controller.finishDrag(at: drop)
        XCTAssertFalse(controller.interacting)
        XCTAssertFalse(overlay.isVisible)
        XCTAssertEqual(store.active.items.map(\.id), [clock.id, folder.id])
        XCTAssertEqual(DockStore(fileURL: url).active.items.map(\.id), [clock.id, folder.id])
    }
}
#endif
