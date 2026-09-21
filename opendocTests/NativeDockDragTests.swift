#if os(macOS)
import AppKit
import QuartzCore
import XCTest
@testable import opendoc

@MainActor
final class NativeDockDragTests: XCTestCase {
    func testFinderHasNewWindowInDockAndInsideFolder() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = DockStore(fileURL: url)
        let finder = NativeApplications.item(for: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"))
        var folder = DockItem(kind: .folder, title: "Files", symbol: "folder")
        folder.children = [finder]
        let profile = DockProfile(name: "Window commands", symbol: "folder", color: "green", items: [folder])
        try store.create(profile)
        let application = MacApplication()
        let dock = NativeDockController(profileID: profile.id, store: store, application: application)
        defer { dock.close() }
        XCTAssertNotNil(dock.menu(for: finder).item(withTitle: "New Window"))
        XCTAssertNotNil(dock.menu(for: finder).item(withTitle: "Open"))
        XCTAssertNil(dock.menu(for: .widget(.clock)).item(withTitle: "New Window"))
        XCTAssertFalse(NativeApplicationWindows.supportsNewWindow(NativeApplications.item(for: Bundle.main.bundleURL)))
        let controller = NativeFolderController(folderID: folder.id, dock: dock)
        func buttons(in view: NSView) -> [NSButton] {
            if let button = view as? NSButton { return [button] }
            return view.subviews.flatMap { buttons(in: $0) }
        }
        let button = try XCTUnwrap(buttons(in: controller.view).first { $0.title == finder.title })
        XCTAssertNotNil(button.menu?.item(withTitle: "New Window"))
        XCTAssertNotNil(button.menu?.item(withTitle: "Open"))
        XCTAssertNotNil(button.menu?.item(withTitle: "Show in Finder"))
        XCTAssertNotNil(button.menu?.item(withTitle: "Move to Dock"))
    }

    func testFolderApplicationMenuIncludesRunningActionsWithoutNewWindowSupport() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = DockStore(fileURL: url)
        let running = NativeApplications.item(for: try XCTUnwrap(NSRunningApplication.current.bundleURL))
        let stopped = NativeApplications.item(for: URL(fileURLWithPath: "/Applications/\(UUID().uuidString).app"))
        var folder = DockItem(kind: .folder, title: "Application actions", symbol: "folder")
        folder.children = [running, stopped]
        let profile = DockProfile(name: "Menus", symbol: "folder", color: "green", items: [folder])
        try store.create(profile)
        let application = MacApplication()
        let dock = NativeDockController(profileID: profile.id, store: store, application: application)
        defer { dock.close() }
        let controller = NativeFolderController(folderID: folder.id, dock: dock)
        func buttons(in view: NSView) -> [NSButton] {
            if let button = view as? NSButton { return [button] }
            return view.subviews.flatMap { buttons(in: $0) }
        }
        for item in [running, stopped] {
            let button = try XCTUnwrap(buttons(in: controller.view).first { $0.title == item.title })
            let menu = try XCTUnwrap(button.menu)
            XCTAssertNotNil(menu.item(withTitle: "Open"))
            XCTAssertNotNil(menu.item(withTitle: "Show in Finder"))
            XCTAssertNil(menu.item(withTitle: "New Window"))
            XCTAssertEqual(menu.item(withTitle: "Quit \(item.title)") != nil, item.id == running.id)
            let visibilityTitle = NSRunningApplication.current.isHidden ? "Show" : "Hide"
            XCTAssertEqual(menu.item(withTitle: visibilityTitle) != nil, item.id == running.id)
            let titles = menu.items.map(\.title)
            let appActions = Array(titles.dropLast(2))
            XCTAssertEqual(appActions, dock.menu(for: item).items.prefix(appActions.count).map(\.title))
            controller.menuNeedsUpdate(menu)
            XCTAssertEqual(menu.items.map(\.title), titles, "Refreshing must not duplicate actions")
        }
    }

    func testFolderPagesKeepSizeAndClampAfterRemovingLastPage() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = DockStore(fileURL: url)
        var folder = DockItem(kind: .folder, title: "Paged folder", symbol: "folder")
        folder.children = (1...19).map { NativeApplications.item(for: URL(fileURLWithPath: "/Applications/App \($0).app")) }
        var profile = DockProfile(name: "Pages", symbol: "folder", color: "green", items: [folder])
        profile.appearance.autoHide = false
        try store.create(profile)
        let application = MacApplication()
        let dock = NativeDockController(profileID: profile.id, store: store, application: application)
        defer { dock.close() }
        dock.showWindow(nil)
        dock.open(folder)
        let controller = try XCTUnwrap(dock.folderController)
        let size = controller.view.frame.size
        func buttons(in view: NSView) -> [NSButton] {
            if let button = view as? NSButton { return [button] }
            return view.subviews.flatMap { buttons(in: $0) }
        }
        func apps() -> [NSButton] { buttons(in: controller.view).filter { $0.title.hasPrefix("App ") } }
        func arrow(_ name: String) throws -> NSButton {
            try XCTUnwrap(buttons(in: controller.view).first { $0.accessibilityLabel() == name })
        }
        XCTAssertEqual(apps().map(\.title), (1...9).map { "App \($0)" })
        XCTAssertEqual(Set(apps().map { $0.frame.minX }).count, 3)
        XCTAssertFalse(try arrow("Previous page").isEnabled)
        try arrow("Next page").performClick(nil)
        XCTAssertEqual(apps().map(\.title), (10...18).map { "App \($0)" })
        XCTAssertEqual(controller.view.frame.size, size)
        try arrow("Next page").performClick(nil)
        XCTAssertEqual(apps().map(\.title), ["App 19"])
        XCTAssertFalse(try arrow("Next page").isEnabled)
        XCTAssertEqual(controller.view.frame.size, size)
        folder.children?.removeLast()
        try store.updateItem(folder)
        XCTAssertEqual(apps().map(\.title), (10...18).map { "App \($0)" })
        XCTAssertEqual(controller.view.frame.size, size)
        try arrow("Previous page").performClick(nil)
        XCTAssertEqual(apps().map(\.title), (1...9).map { "App \($0)" })
        folder.children = Array((folder.children ?? []).prefix(5))
        try store.updateItem(folder)
        XCTAssertEqual(apps().count, 5)
        XCTAssertEqual(Set(apps().map { $0.frame.minX }).count, 3)
        XCTAssertEqual(Set(apps().map { $0.frame.minY }).count, 2)
        XCTAssertLessThan(controller.view.frame.height, size.height)
        XCTAssertFalse(buttons(in: controller.view).contains { $0.accessibilityLabel() == "Next page" })
    }

    func testClickingAnotherFolderSwitchesImmediatelyAndSameFolderCloses() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = DockStore(fileURL: url)
        let application = MacApplication()
        for position in ["Bottom", "Left", "Right"] {
            var first = DockItem(kind: .folder, title: "First", symbol: "folder")
            var second = DockItem(kind: .folder, title: "Second", symbol: "folder")
            first.children = []; second.children = []
            var profile = DockProfile(name: "Folder switching", symbol: "folder", color: "green", items: [first, second])
            profile.appearance.autoHide = false
            profile.appearance.position = position
            try store.create(profile)
            let controller = NativeDockController(profileID: profile.id, store: store, application: application)
            defer { controller.close() }
            controller.showWindow(nil)
            for item in [first, second, first, second] {
                let previous = controller.folderController
                controller.open(item)
                XCTAssertEqual(controller.folderController?.folderID, item.id)
                XCTAssertEqual(controller.folderController?.isShown, true, "\(position): \(item.title)")
                XCTAssertTrue(controller.interacting)
                if let previous { XCTAssertFalse(previous.isShown) }
                RunLoop.main.run(until: Date().addingTimeInterval(0.25))
                XCTAssertEqual(controller.folderController?.isShown, true)
                XCTAssertTrue(controller.interacting, "Previous dismissal must not clear the new folder's interaction")
            }
            // AppKit can attach a tooltip or another auxiliary window to the
            // popover. An explicit folder toggle must still close it.
            let popoverWindow = try XCTUnwrap(controller.folderController?.view.window)
            let auxiliary = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 40, height: 20),
                                    styleMask: .borderless, backing: .buffered, defer: false)
            popoverWindow.addChildWindow(auxiliary, ordered: .above)
            defer { popoverWindow.removeChildWindow(auxiliary); auxiliary.orderOut(nil) }
            controller.open(second)
            let deadline = Date().addingTimeInterval(3)
            while controller.folderController?.isShown == true, Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            }
            XCTAssertEqual(controller.folderController?.isShown, false, "\(position): explicit toggle must close with an auxiliary window")
            XCTAssertFalse(controller.interacting, "\(position): closed folder must release interaction")
        }
    }

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
        let root = try XCTUnwrap(controller.window?.contentView)
        func tiles(in view: NSView) -> [NativeDockItemView] {
            if let tile = view as? NativeDockItemView { return [tile] }
            return view.subviews.flatMap { tiles(in: $0) }
        }
        let tile = try XCTUnwrap(tiles(in: root).first { $0.item.id == folder.id })
        let glass = tile.animationView
        let originalParent = glass.superview
        let originalFrame = glass.frame
        let shelfSize = root.bounds.size
        func image(in view: NSView) -> NSImageView? {
            (view as? NSImageView) ?? view.subviews.compactMap { image(in: $0) }.first
        }
        let preview = try XCTUnwrap(image(in: glass))
        let oldImage = preview.image
        controller.previewMagnification()
        let overlay = try XCTUnwrap(controller.window?.childWindows?.first)
        let magnifier = try XCTUnwrap(overlay.windowController as? NativeDockMagnification)
        XCTAssertTrue(root.window === overlay)
        XCTAssertTrue(glass.superview === originalParent, "The folder must stay embedded in its original tile and shelf")
        XCTAssertEqual(root.bounds.size, shelfSize)
        XCTAssertEqual(glass.alphaValue, 1)
        XCTAssertFalse(glass.isHidden)
        let anchor = try XCTUnwrap(magnifier.popoverAnchor(for: folder.id))
        let point = overlay.convertPoint(toScreen: NSPoint(x: anchor.rect.midX, y: anchor.rect.midY))
        magnifier.update(at: point, animated: false)
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
        XCTAssertFalse(oldImage === preview.image)
        controller.endMagnification()
        XCTAssertTrue(controller.window?.contentView === root)
        XCTAssertTrue(glass.superview === originalParent)
        XCTAssertEqual(glass.frame, originalFrame)
        XCTAssertEqual(root.bounds.size, shelfSize)
    }

    func testHoverExitKeepsOriginalViewsAndRestoresGeometry() throws {
        try XCTSkipIf(NativeMotion.reducesMotion, "Magnification is disabled by Reduce Motion.")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = DockStore(fileURL: url)
        let app = NativeApplications.item(for: Bundle.main.bundleURL)
        var folder = DockItem(kind: .folder, title: "Tools", symbol: "folder")
        folder.children = [app]
        var profile = DockProfile(name: "Hover", symbol: "folder", color: "green", items: [folder, .widget(.clock)])
        profile.appearance.autoHide = false
        try store.create(profile)
        let application = MacApplication()
        let controller = NativeDockController(profileID: profile.id, store: store, application: application)
        defer { controller.close() }
        let root = try XCTUnwrap(controller.window?.contentView)
        root.layoutSubtreeIfNeeded()
        func tiles(in view: NSView) -> [NativeDockItemView] {
            if let tile = view as? NativeDockItemView { return [tile] }
            return view.subviews.flatMap { tiles(in: $0) }
        }
        let views = tiles(in: root)
        let originalFrames = views.map { $0.animationView.frame }
        let originalParents = views.map { $0.animationView.superview }
        let folderTile = try XCTUnwrap(views.first { $0.item.id == folder.id })
        let host = folderTile.animationView
        let contentFrames = host.subviews.map(\.frame)
        for _ in 0..<3 {
            controller.previewMagnification()
            let overlay = try XCTUnwrap(controller.window?.childWindows?.first)
            let magnifier = try XCTUnwrap(overlay.windowController as? NativeDockMagnification)
            let anchor = try XCTUnwrap(magnifier.popoverAnchor(for: folder.id))
            let point = overlay.convertPoint(toScreen: NSPoint(x: anchor.rect.midX, y: anchor.rect.midY))
            magnifier.update(at: point, animated: false)
            CATransaction.flush()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            let lifted = try XCTUnwrap(magnifier.popoverAnchor(for: folder.id)).rect
            XCTAssertGreaterThan(lifted.maxY, root.frame.maxY, "The folder must visibly rise beyond the shelf")
            var ancestor = host.superview
            while let view = ancestor, view !== overlay.contentView {
                XCTAssertFalse(view is NSClipView)
                if #available(macOS 26.0, *) { XCTAssertFalse(view is NSGlassEffectView) }
                XCTAssertFalse(view.clipsToBounds)
                ancestor = view.superview
            }
            XCTAssertEqual(host.subviews.map(\.frame), contentFrames, "Magnification must not relayout folder glass or artwork")
            for offset in [-12.0, 15.0, -5.0, 0.0] {
                magnifier.update(at: NSPoint(x: point.x + offset, y: point.y))
                XCTAssertEqual(host.subviews.map(\.frame), contentFrames)
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            magnifier.update(at: point, magnified: false)
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            for (index, tile) in views.enumerated() {
                XCTAssertTrue(tile.animationView.superview === originalParents[index])
                XCTAssertEqual(tile.animationView.frame.minX, originalFrames[index].minX, accuracy: 0.5)
                XCTAssertEqual(tile.animationView.frame.minY, originalFrames[index].minY, accuracy: 0.5)
                XCTAssertEqual(tile.animationView.frame.width, originalFrames[index].width, accuracy: 0.5)
                XCTAssertEqual(tile.animationView.alphaValue, 1)
            }
            controller.endMagnification()
            XCTAssertTrue(controller.window?.contentView === root)
            XCTAssertEqual(views.map { $0.animationView.frame }, originalFrames)
        }
    }

    func testFolderCountsDistinctRunningAppsAndTracksExits() {
        let a = URL(fileURLWithPath: "/Applications/A.app")
        let b = URL(fileURLWithPath: "/Applications/B.app")
        let other = URL(fileURLWithPath: "/Applications/Other.app")
        var folder = DockItem(kind: .folder, title: "Tools", symbol: "folder")
        folder.children = [NativeApplications.item(for: a), NativeApplications.item(for: b), NativeApplications.item(for: a)]
        XCTAssertEqual(NativeApplications.runningCount(folder, runningURLs: [a, b, a, other]), 2)
        XCTAssertEqual(NativeApplications.runningCount(folder, runningURLs: [b, other]), 1)
        XCTAssertEqual(NativeApplications.runningCount(folder, runningURLs: [other]), 0)
        XCTAssertEqual(NativeApplications.runningCount(NativeApplications.item(for: a), runningURLs: [a, a]), 1)
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
        XCTAssertTrue(panel.contentView === root)
        XCTAssertTrue(source.animationView.superview === source)
        XCTAssertFalse(source.animationView.isHidden)
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
