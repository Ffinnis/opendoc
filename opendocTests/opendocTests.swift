import XCTest
#if os(macOS)
import AppKit
import QuartzCore
#endif
@testable import opendoc

@MainActor
final class opendocTests: XCTestCase {
    private func makeStore() -> DockStore {
        DockStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID()).json"))
    }

    func testPersistenceAndAppearance() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let store = DockStore(fileURL: file)
        try store.create(name: "Writing")
        var note = DockItem.widget(.note)
        note.note = "Chapter two"
        try store.add(note)
        var profile = store.active
        profile.appearance.position = "Left"
        try store.update(profile)
        let reloaded = DockStore(fileURL: file)
        XCTAssertEqual(reloaded.active.name, "Writing")
        XCTAssertEqual(reloaded.active.items.first?.note, "Chapter two")
        XCTAssertEqual(reloaded.active.appearance.position, "Left")
    }

    func testDuplicateAndImportHaveIndependentIDs() throws {
        let store = makeStore()
        let original = store.active
        try store.create(name: "Copy", duplicate: true)
        XCTAssertEqual(store.active.items.count, original.items.count)
        XCTAssertTrue(Set(store.active.items.map(\.id)).isDisjoint(with: original.items.map(\.id)))
        let active = store.active.id
        let count = store.archive.profiles.count
        try store.importData(store.exportData())
        XCTAssertEqual(store.archive.profiles.count, count * 2)
        XCTAssertEqual(store.active.id, active)
        try store.archive.validate()
    }

    func testInvalidImportIsAtomic() throws {
        let store = makeStore()
        try store.create(name: "Saved")
        let before = try store.exportData()
        var invalid = store.archive
        invalid.profiles[0].appearance.size = -5
        XCTAssertThrowsError(try store.importData(JSONEncoder().encode(invalid)))
        XCTAssertEqual(try store.exportData(), before)
        XCTAssertThrowsError(try store.importData(Data("not json".utf8)))
        XCTAssertEqual(store.active.name, "Saved")
    }

    func testCorruptWorkspaceIsPreserved() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let corrupt = Data("corrupt workspace".utf8)
        try corrupt.write(to: file)
        let store = DockStore(fileURL: file)
        XCTAssertNotNil(store.loadError)
        XCTAssertThrowsError(try store.create(name: "Do not overwrite"))
        XCTAssertEqual(try Data(contentsOf: file), corrupt)
    }

    func testCannotDeleteLastDock() throws {
        let store = makeStore()
        while store.archive.profiles.count > 1 { try store.deleteActive() }
        XCTAssertThrowsError(try store.deleteActive())
        XCTAssertEqual(store.archive.profiles.count, 1)
    }

    func testConfiguredProfileCreationIsAtomicAndUndoable() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("create-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let store = DockStore(fileURL: file)
        let before = try store.exportData()
        var profile = DockProfile(name: "Desktop", symbol: "square.grid.2x2", color: "green", items: [.widget(.clock)])
        profile.appearance.size = -1
        XCTAssertThrowsError(try store.create(profile))
        XCTAssertEqual(try store.exportData(), before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        profile.appearance.size = 48
        store.undoManager.beginUndoGrouping()
        try store.create(profile)
        store.undoManager.endUndoGrouping()
        XCTAssertEqual(store.active.id, profile.id)
        XCTAssertEqual(DockStore(fileURL: file).active.items.first?.id, profile.items.first?.id)
        store.undoManager.undo()
        XCTAssertEqual(try store.exportData(), before)
    }

    func testTimersUseElapsedTime() {
        let start = Date(timeIntervalSince1970: 1000)
        var focus = DockItem.widget(.focus)
        focus.startedAt = start
        XCTAssertEqual(focus.timerValue(at: start.addingTimeInterval(40)), 1460)
        XCTAssertEqual(focus.timerValue(at: start.addingTimeInterval(2000)), 0)
        var stopwatch = DockItem.widget(.stopwatch)
        stopwatch.startedAt = start
        stopwatch.remaining = 10
        XCTAssertEqual(stopwatch.timerValue(at: start.addingTimeInterval(40)), 50)
    }

    func testHydrationResetsOnNewDay() {
        var hydration = DockItem.widget(.hydration)
        hydration.count = 5
        hydration.countDay = "2000-1-1"
        XCTAssertEqual(hydration.dailyCount, 0)
        hydration.countDay = DockItem.dayKey()
        XCTAssertEqual(hydration.dailyCount, 5)
    }

    func testShortcutValidation() {
        XCTAssertNil(DockArchive.allowedURL("javascript:alert(1)"))
        XCTAssertNil(DockArchive.allowedURL("file:///etc/passwd"))
        XCTAssertNil(DockArchive.allowedURL("https://"))
        XCTAssertNotNil(DockArchive.allowedURL("https://example.com"))
        XCTAssertNotNil(DockArchive.allowedURL("shortcuts://run-shortcut?name=Work"))
    }

    func testOpenDockEditsStayInTheirOwnProfile() throws {
        let store = makeStore()
        let originalID = store.active.id
        var note = try XCTUnwrap(store.active.items.first(where: { $0.widget == .note }))
        try store.select(store.archive.profiles[1].id)
        note.note = "Updated from a separate dock window"
        try store.updateItem(note)
        XCTAssertFalse(store.active.items.contains(where: { $0.id == note.id }))
        try store.add(.widget(.custom), to: originalID)
        try store.select(originalID)
        XCTAssertEqual(store.active.items.first(where: { $0.id == note.id })?.note, note.note)
        XCTAssertEqual(store.active.items.last?.widget, .custom)
    }

    func testOutOfRangeTimerArchiveIsRejected() throws {
        var archive = DockStore.initialArchive()
        archive.profiles[0].items[0].remaining = 1e100
        XCTAssertThrowsError(try archive.validate())
    }

    func testApplicationReferencesMustBeAppBundles() throws {
        let store = makeStore()
        let application = DockItem(kind: .application, title: "Finder", symbol: "app", url: "file:///System/Library/CoreServices/Finder.app")
        try store.add(application)
        let before = try store.exportData()
        var invalid = application
        invalid.id = UUID()
        invalid.url = "file:///bin/sh"
        XCTAssertThrowsError(try store.add(invalid))
        XCTAssertEqual(try store.exportData(), before)
    }

    func testFoldersPreserveApplicationsAndUngroupOrder() throws {
        let store = makeStore()
        try store.create(name: "Folder checks")
        let first = DockItem(kind: .application, title: "A", symbol: "app", url: "file:///Applications/A.app")
        let second = DockItem(kind: .application, title: "B", symbol: "app", url: "file:///Applications/B.app")
        let third = DockItem(kind: .application, title: "C", symbol: "app", url: "file:///Applications/C.app")
        try store.add(first); try store.add(second); try store.add(third)
        try store.groupApplications([first.id, second.id], in: store.active.id, name: "Tools")
        let folder = try XCTUnwrap(store.active.items.first)
        XCTAssertEqual(folder.children?.map(\.id), [first.id, second.id])
        try store.addApplications([third], into: folder.id, in: store.active.id)
        XCTAssertEqual(store.active.items.count, 1)
        try store.moveOutOfFolder(second.id, folderID: folder.id, in: store.active.id)
        XCTAssertEqual(store.active.items.last?.id, second.id)
        try store.ungroupFolder(folder.id, in: store.active.id)
        XCTAssertEqual(store.active.items.map(\.id), [first.id, third.id, second.id])
    }

    func testDraggingRunningAppPinsAcrossSeparatorAndMovesIntoFolder() throws {
        let store = makeStore()
        try store.create(name: "Running apps")
        let separator = DockItem(kind: .spacer, title: "Separator", symbol: "line.3.horizontal")
        var folder = DockItem(kind: .folder, title: "Development", symbol: "folder")
        folder.children = []
        let app = DockItem(kind: .application, title: "Simulator", symbol: "app", url: "file:///Applications/Simulator.app")
        try store.add(folder); try store.add(separator)
        let before = try store.exportData()
        store.undoManager.removeAllActions()
        try store.drop(app, relativeTo: separator.id, placement: .before, in: store.active.id)
        XCTAssertEqual(store.active.items.map(\.id), [folder.id, app.id, separator.id])
        store.undoManager.undo()
        XCTAssertEqual(try store.exportData(), before)
        try store.drop(app, relativeTo: folder.id, placement: .group, in: store.active.id)
        XCTAssertEqual(store.active.items.map(\.id), [folder.id, separator.id])
        XCTAssertEqual(store.active.items.first?.children?.map(\.id), [app.id])
    }

    func testReorderKeepsEditsMadeDuringDrag() throws {
        let store = makeStore()
        try store.create(name: "Concurrent edit")
        let clock = DockItem.widget(.clock)
        let note = DockItem.widget(.note)
        try store.add(clock); try store.add(note)
        var updated = clock
        updated.title = "Edited during drag"
        try store.updateItem(updated)
        try store.drop(clock, relativeTo: note.id, placement: .after, in: store.active.id)
        XCTAssertEqual(store.active.items.map(\.id), [note.id, clock.id])
        XCTAssertEqual(store.active.items.last?.title, updated.title)
    }

    func testAddingFolderAppsMovesPinnedItemsWithoutDuplicatesAndCanUndo() throws {
        let store = makeStore()
        try store.create(name: "Folder moves")
        let app = DockItem(kind: .application, title: "A", symbol: "app", url: "file:///Applications/A.app")
        var folder = DockItem(kind: .folder, title: "Tools", symbol: "folder")
        folder.children = []
        try store.add(app); try store.add(folder)
        let before = try store.exportData()
        store.undoManager.removeAllActions()
        var duplicate = app
        duplicate.id = UUID()
        duplicate.url = "file:///Applications/../Applications/A.app"
        try store.addApplications([duplicate, app], into: folder.id, in: store.active.id)
        XCTAssertEqual(store.active.items.map(\.id), [folder.id])
        XCTAssertEqual(store.active.items.first?.children?.map(\.id), [app.id])
        store.undoManager.undo()
        XCTAssertEqual(try store.exportData(), before)
        XCTAssertThrowsError(try store.addApplications([.widget(.clock)], into: folder.id, in: store.active.id))
        XCTAssertEqual(try store.exportData(), before)
    }

    func testFolderCopiesUseIndependentChildIDsAndRejectNesting() throws {
        let store = makeStore()
        try store.create(name: "Folders")
        var folder = DockItem(kind: .folder, title: "Tools", symbol: "folder")
        folder.children = [DockItem(kind: .application, title: "A", symbol: "app", url: "file:///Applications/A.app")]
        try store.add(folder)
        try store.create(name: "Copy", duplicate: true)
        XCTAssertNotEqual(store.active.items.first?.children?.first?.id, folder.children?.first?.id)
        try store.importData(store.exportData())
        try store.archive.validate()
        let before = try store.exportData()
        folder.id = UUID()
        folder.children = [folder.independentCopy()]
        XCTAssertThrowsError(try store.add(folder))
        XCTAssertEqual(try store.exportData(), before)
    }

    func testWebWidgetJSONPathsAndLimits() throws {
        let data = Data(#"{"data":{"readings":[{"value":42.5}]}}"#.utf8)
        var configuration = WebWidgetConfiguration(endpoint: "https://example.com/value", keyPath: "data.readings.0.value", suffix: "%")
        XCTAssertEqual(try configuration.value(in: data), "42.5%")
        configuration.keyPath = "data.readings.3.value"
        XCTAssertThrowsError(try configuration.value(in: data))
        configuration.keyPath = "data"
        XCTAssertThrowsError(try configuration.value(in: data))
        configuration.keyPath = ""; configuration.suffix = ""
        XCTAssertEqual(try configuration.value(in: Data("123".utf8)), "123")
        XCTAssertThrowsError(try configuration.value(in: Data(repeating: 32, count: 1_048_577)))
        configuration.endpoint = "file:///etc/passwd"
        XCTAssertThrowsError(try configuration.validate())
        configuration.endpoint = "https://example.com/value"; configuration.refreshInterval = 0
        XCTAssertThrowsError(try configuration.validate())
    }

    func testCustomWidgetStatePersistenceAndDailyReset() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("custom-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let store = DockStore(fileURL: file)
        var item = DockItem.widget(.custom)
        var config = CustomWidgetConfiguration.water()
        config.state = ["count": 3, "goal": 8]; config.stateDay = "2026-09-20"
        item.custom = config
        try store.add(item)
        let restored = DockStore(fileURL: file).active.items.first { $0.id == item.id }
        XCTAssertEqual(restored?.custom, config)
        XCTAssertEqual(config.effectiveState(day: "2026-09-20")["count"], 3)
        XCTAssertEqual(config.effectiveState(day: "2026-09-21")["count"], 0)
        config.resetDaily = false
        XCTAssertEqual(config.effectiveState(day: "2026-09-21")["count"], 3)
        item.custom = nil
        let legacy = try JSONDecoder().decode(DockItem.self, from: JSONEncoder().encode(item))
        XCTAssertNil(legacy.custom)
    }

    func testCustomWidgetRejectsInvalidConfiguration() throws {
        var config = CustomWidgetConfiguration.webpage()
        XCTAssertThrowsError(try config.validate())
        config.endpoint = "https://example.com"; config.selector = ".price"
        XCTAssertNoThrow(try config.validate())
        config.endpoint = "file:///etc/passwd"
        XCTAssertThrowsError(try config.validate())
        config = CustomWidgetConfiguration()
        config.actions.append(contentsOf: config.actions)
        XCTAssertThrowsError(try config.validate())
        config = CustomWidgetConfiguration(); config.state["count"] = .infinity
        XCTAssertThrowsError(try config.validate())
    }

    func testUndoRestoresRemovedFolderWithItsChildren() throws {
        let store = makeStore()
        try store.create(name: "Undo")
        var folder = DockItem(kind: .folder, title: "Tools", symbol: "folder")
        folder.children = [DockItem(kind: .application, title: "A", symbol: "app", url: "file:///Applications/A.app")]
        try store.add(folder)
        store.undoManager.removeAllActions()
        store.undoManager.beginUndoGrouping()
        var profile = store.active; profile.items = []
        try store.update(profile)
        store.undoManager.endUndoGrouping()
        store.undoManager.undo()
        XCTAssertEqual(store.active.items.first?.children?.first?.id, folder.children?.first?.id)
        store.undoManager.redo()
        XCTAssertTrue(store.active.items.isEmpty)
    }

    #if os(macOS)
    func testSystemDockLockSurvivesSnapshotReplacementAndReleasesAfterError() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("dock-lock-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshot = directory.appendingPathComponent("session.json")
        XCTAssertThrowsError(try SystemDockSession.withSessionLock(at: snapshot) {
            try Data("first".utf8).write(to: snapshot, options: .atomic)
            let competing = open(snapshot.appendingPathExtension("lock").path, O_RDWR)
            XCTAssertGreaterThanOrEqual(competing, 0)
            defer { close(competing) }
            XCTAssertEqual(flock(competing, LOCK_EX | LOCK_NB), -1)
            XCTAssertEqual(errno, EWOULDBLOCK)
            try Data("replacement".utf8).write(to: snapshot, options: .atomic)
            XCTAssertEqual(flock(competing, LOCK_EX | LOCK_NB), -1)
            throw CocoaError(.userCancelled)
        })
        let descriptor = open(snapshot.appendingPathExtension("lock").path, O_RDWR)
        defer { close(descriptor) }
        XCTAssertEqual(flock(descriptor, LOCK_EX | LOCK_NB), 0)
    }

    func testOldDockWatcherCannotRemoveAnotherOwnersSnapshot() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("dock-owner-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("session.json")
        let data = try JSONEncoder().encode(SystemDockSession.Snapshot(ownerPID: getpid(), autoHide: false, delay: nil))
        try data.write(to: url)
        try SystemDockSession.restore(at: url, expectedOwner: -1)
        XCTAssertEqual(try Data(contentsOf: url), data)
    }

    func testMagnificationCoordinatesFollowRevealingParent() {
        let screen = CGRect(x: -1920, y: 120, width: 1920, height: 1080)
        for y in stride(from: screen.minY - 63, through: screen.minY + 8, by: 1) {
            let parent = CGRect(x: -1500, y: y, width: 800, height: 66)
            let overlay = NativeDockWave.overlayFrame(parent: parent, screen: screen)
            let itemInWindow = CGRect(x: 16, y: 8, width: 44, height: 44)
            let itemInOverlay = itemInWindow.offsetBy(dx: parent.minX - overlay.minX, dy: parent.minY - overlay.minY)
            XCTAssertEqual(itemInOverlay.minY, 8, "Hidden and revealing panels must keep positive local coordinates")
            XCTAssertTrue(CGRect(origin: .zero, size: overlay.size).contains(itemInOverlay))
            XCTAssertGreaterThanOrEqual(overlay.minX, screen.minX)
            XCTAssertLessThanOrEqual(overlay.maxX, screen.maxX)
        }
    }

    func testMagnificationApproachIsContinuous() {
        let base = (0..<7).map { CGRect(x: Double($0) * 110, y: 8, width: 44, height: 44) }
        let kinds = [true, true, false, true, true, true, true]
        XCTAssertEqual(NativeDockWave.layout(base: base, magnifiable: kinds, pointerX: nil, pointerY: nil), base)
        var previous = base[3].width
        for distance in stride(from: 120.0, through: 0, by: -1) {
            let result = NativeDockWave.layout(base: base, magnifiable: kinds,
                pointerX: base[3].midX, pointerY: base[3].maxY + distance)
            XCTAssertEqual(result[2].size, base[2].size, "Widgets keep their size")
            XCTAssertGreaterThanOrEqual(result[3].width, previous)
            XCTAssertLessThan(result[3].width - previous, 0.3, "Crossing the row edge must not jump in size")
            previous = result[3].width
        }
        XCTAssertEqual(previous, base[3].width * (1 + NativeDockWave.maximumGrowth), accuracy: 0.0001)
    }

    func testReducedMotionOpensWidgetOnRestingDock() throws {
        try XCTSkipUnless(NativeMotion.reducesMotion, "Runs with Reduce Motion enabled.")
        let store = makeStore()
        var profile = store.active
        let clock = DockItem.widget(.clock)
        profile.items = [clock]
        profile.appearance.autoHide = false
        try store.update(profile)
        let dock = NativeDockController(profileID: profile.id, store: store, application: MacApplication())
        defer { dock.close() }
        dock.showWindow(nil)
        dock.previewMagnification()
        XCTAssertTrue(dock.window?.isVisible == true)
        XCTAssertFalse(dock.window?.childWindows?.contains { $0.title == "Dock Magnification" } == true)
        dock.open(clock)
        XCTAssertFalse(dock.window?.childWindows?.isEmpty ?? true)
    }

    func testOpeningWidgetKeepsMagnifiedRowAndPopoverAnchor() throws {
        try XCTSkipIf(NativeMotion.reducesMotion, "Magnification is disabled by Reduce Motion.")
        let store = makeStore()
        var profile = store.active
        let clock = DockItem.widget(.clock)
        profile.items = [clock]
        profile.appearance.position = "Bottom"
        profile.appearance.autoHide = false
        try store.update(profile)
        let dock = NativeDockController(profileID: profile.id, store: store, application: MacApplication())
        defer { dock.close() }
        dock.showWindow(nil)
        dock.previewMagnification()
        let overlay = try XCTUnwrap(dock.window?.childWindows?.first { $0.title == "Dock Magnification" }, "Reduce Motion: \(NativeMotion.reducesMotion), screens: \(NSScreen.screens.map(\.frame)), dock: \(String(describing: dock.window?.frame))")
        dock.open(clock)
        XCTAssertTrue(overlay.isVisible, "Opening a widget must not collapse the magnified row")
        XCTAssertTrue(dock.window?.childWindows?.contains { $0 === overlay } == true)
        XCTAssertFalse(overlay.childWindows?.isEmpty ?? true, "Popover must stay anchored to the magnified window")
    }

    func testNativeDockReorderingPreservesOtherProfiles() throws {
        let store = makeStore()
        let id = store.active.id
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let untouched = try encoder.encode(store.archive.profiles[1])
        let original = store.active.items.map(\.id)
        XCTAssertGreaterThan(original.count, 1)
        let first = try XCTUnwrap(store.active.items.first)
        try store.drop(first, relativeTo: original.last!, placement: .after, in: id)
        XCTAssertEqual(store.active.items.last?.id, original[0])
        XCTAssertEqual(try encoder.encode(store.archive.profiles[1]), untouched)
        try store.drop(first, relativeTo: original[1], placement: .before, in: id)
        XCTAssertEqual(store.active.items.map(\.id), original)
        XCTAssertThrowsError(try store.drop(.widget(.clock), relativeTo: original[0], placement: .after, in: id))
        XCTAssertEqual(store.active.items.map(\.id), original)
    }

    func testNativeDockSupportsHorizontalAndVerticalGeometry() throws {
        let store = makeStore()
        var profile = store.active
        profile.items = [.widget(.clock), .widget(.hydration)]
        profile.appearance.position = "Bottom"
        try store.update(profile)
        let app = MacApplication()
        let dock = NativeDockController(profileID: profile.id, store: store, application: app)
        defer { dock.close() }
        let horizontal = try XCTUnwrap(dock.window?.frame)
        XCTAssertGreaterThan(horizontal.width, horizontal.height)
        profile.appearance.position = "Right"
        try store.update(profile)
        dock.reload()
        let vertical = try XCTUnwrap(dock.window?.frame)
        XCTAssertGreaterThan(vertical.height, vertical.width)
        XCTAssertEqual(store.active.items.map(\.widget), [.clock, .hydration])
    }
    func testNativeAutoHideReturnsToItsVisibleFrame() throws {
        let store = makeStore()
        let screen = try XCTUnwrap(NSScreen.main)
        var profile = store.active
        profile.items = [.widget(.clock)]
        profile.appearance.position = NSEvent.mouseLocation.x > screen.frame.midX ? "Left" : "Right"
        profile.appearance.autoHide = true
        try store.update(profile)
        let app = MacApplication()
        let dock = NativeDockController(profileID: profile.id, store: store, application: app)
        defer { dock.close() }
        dock.showWindow(nil)
        let visible = try XCTUnwrap(dock.window?.frame)
        RunLoop.current.run(until: Date().addingTimeInterval(1.4))
        let hidden = try XCTUnwrap(dock.window?.frame)
        XCTAssertNotEqual(hidden.origin, visible.origin)
        if profile.appearance.position == "Left" {
            XCTAssertEqual(hidden.maxX, screen.frame.minX + 3, accuracy: 1)
        } else {
            XCTAssertEqual(hidden.minX, screen.frame.maxX - 3, accuracy: 1)
        }
        dock.reveal()
        RunLoop.current.run(until: Date().addingTimeInterval(0.28))
        XCTAssertEqual(dock.window?.frame, visible)
    }

    func testRevealRequiresContinuousHoverAndCancelsOnExit() {
        var dwell = NativeDockVisibility.RevealDwell()
        XCTAssertFalse(dwell.update(isInside: true, at: 10))
        XCTAssertFalse(dwell.update(isInside: true, at: 10.20))
        XCTAssertFalse(dwell.update(isInside: false, at: 10.25))
        XCTAssertFalse(dwell.update(isInside: true, at: 11))
        XCTAssertFalse(dwell.update(isInside: true, at: 11.20))
        XCTAssertTrue(dwell.update(isInside: true, at: 11.30))
        dwell.reset()
        XCTAssertFalse(dwell.update(isInside: true, at: 12))
    }

    func testDockActivationAreaIncludesEdgeGapOnOffsetDisplays() {
        let screen = NSRect(x: -1920, y: 120, width: 1920, height: 1080)
        let bottom = NSRect(x: -1500, y: 128, width: 800, height: 66)
        let area = NativeDockVisibility.activationArea(bottom, screen: screen, edge: "Bottom")
        let reveal = NativeDockVisibility.revealArea(bottom, screen: screen, edge: "Bottom")
        XCTAssertTrue(reveal.contains(NSPoint(x: -1100, y: 121)))
        XCTAssertTrue(reveal.contains(NSPoint(x: -1100, y: 125)))
        XCTAssertFalse(reveal.contains(NSPoint(x: -1100, y: 129)))
        XCTAssertFalse(reveal.contains(NSPoint(x: -1100, y: 180)), "Video controls above the edge must not reveal the dock")
        XCTAssertTrue(area.contains(NSPoint(x: -1100, y: 121)))
        XCTAssertTrue(area.contains(NSPoint(x: -1100, y: 180)))
        XCTAssertFalse(area.contains(NSPoint(x: -1700, y: 121)))
        XCTAssertFalse(area.contains(NSPoint(x: -1100, y: 240)))
        XCTAssertEqual(NativeDockVisibility.hiddenFrame(bottom, screen: screen, edge: "Bottom").maxY, screen.minY + 3)
        let left = NSRect(x: -1912, y: 400, width: 84, height: 250)
        XCTAssertTrue(NativeDockVisibility.activationArea(left, screen: screen, edge: "Left").contains(NSPoint(x: -1919, y: 500)))
        XCTAssertEqual(NativeDockVisibility.hiddenFrame(left, screen: screen, edge: "Left").maxX, screen.minX + 3)
        let right = NSRect(x: -92, y: 400, width: 84, height: 250)
        XCTAssertTrue(NativeDockVisibility.activationArea(right, screen: screen, edge: "Right").contains(NSPoint(x: -1, y: 500)))
        XCTAssertEqual(NativeDockVisibility.hiddenFrame(right, screen: screen, edge: "Right").minX, screen.maxX - 3)
    }
    #endif

}
