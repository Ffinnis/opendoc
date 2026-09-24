#if os(macOS)
import XCTest
import AppKit
import QuartzCore
@testable import opendoc

final class DockEdgeLayoutTests: XCTestCase {
    @MainActor
    func testFittingRowHasNoGlassOrScrollClipAncestor() {
        let root = DockGlassRoot(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
        let row = FlippedNativeView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        root.setDocumentView(row)
        root.layoutSubtreeIfNeeded()
        XCTAssertTrue(row.superview === root)
        XCTAssertFalse(row.clipsToBounds)
        XCTAssertFalse(root.clipsToBounds)
        XCTAssertNil(root.scroll.documentView)

        root.setFrameSize(NSSize(width: 200, height: 100))
        root.needsLayout = true
        root.layoutSubtreeIfNeeded()
        XCTAssertTrue(root.scroll.documentView === row, "Overflow must still scroll and clip widgets")
        XCTAssertTrue(row.superview is NSClipView)
        XCTAssertFalse(root.scroll.isHidden)

        root.setFrameSize(NSSize(width: 400, height: 100))
        root.needsLayout = true
        root.layoutSubtreeIfNeeded()
        XCTAssertTrue(row.superview === root)
        XCTAssertNil(root.scroll.documentView)
        XCTAssertEqual(row.frame.origin, .zero)
    }

    func testHostTransformMovesArtworkWithoutResizingItsBounds() throws {
        for anchor in [CGPoint.zero, CGPoint(x: 0.5, y: 0.5)] {
            let layer = CALayer()
            layer.anchorPoint = anchor
            let base = CGRect(x: 12, y: 5, width: 62, height: 62)
            layer.frame = base
            let target = CGRect(x: 8, y: -20, width: 78, height: 78)
            NativeDockWave.transform(layer, from: base, to: target, duration: 0)
            XCTAssertEqual(layer.bounds.size, base.size)
            XCTAssertEqual(layer.frame.minX, target.minX, accuracy: 0.001)
            XCTAssertEqual(layer.frame.minY, target.minY, accuracy: 0.001)
            XCTAssertEqual(layer.frame.width, target.width, accuracy: 0.001)
            NativeDockWave.transform(layer, from: base, to: base, duration: 0)
            XCTAssertTrue(CATransform3DIsIdentity(layer.transform))
            XCTAssertEqual(layer.frame, base)

            NativeDockWave.transform(layer, from: base, to: target, duration: 0.16)
            NativeDockWave.transform(layer, from: base, to: target.offsetBy(dx: 2, dy: 0), duration: 0.085)
            let animation = try XCTUnwrap(layer.animation(forKey: "dockArtworkTransform") as? CABasicAnimation)
            let from = try XCTUnwrap(animation.fromValue as? NSValue).caTransform3DValue
            XCTAssertTrue(CATransform3DIsIdentity(from), "Retargeting before the first display commit must retain the visible start")
            NativeDockWave.transform(layer, from: base, to: base, duration: 0)
            XCTAssertNil(layer.animation(forKey: "dockArtworkTransform"))
        }
    }

    func testRowSpreadsEvenlyAndWidgetsKeepTheirSizeDuringHover() {
        let base = [CGRect(x: 128, y: 6, width: 126, height: 72),
                    CGRect(x: 260, y: 9, width: 62, height: 62),
                    CGRect(x: 332, y: 9, width: 62, height: 62),
                    CGRect(x: 404, y: 6, width: 126, height: 72)]
        for x in stride(from: 100.0, through: 580, by: 2) {
            let result = NativeDockWave.layout(base: base, magnifiable: [false, true, true, false], pointerX: x,
                                               pointerY: 35)
            // Widgets slide with the row but never change size or baseline.
            XCTAssertEqual(result[0].size, base[0].size)
            XCTAssertEqual(result[3].size, base[3].size)
            XCTAssertEqual(result[0].minY, base[0].minY)
            for i in base.indices {
                XCTAssertEqual(result[i].minY, base[i].minY, "Icons grow upward from the shelf")
                XCTAssertGreaterThanOrEqual(result[i].width, base[i].width)
                XCTAssertLessThanOrEqual(result[i].width, base[i].width * (1 + NativeDockWave.maximumGrowth) + 0.001)
                guard i > 0 else { continue }
                XCTAssertEqual(result[i].minX - result[i - 1].maxX, base[i].minX - base[i - 1].maxX, accuracy: 0.001, "Gaps are preserved")
            }
            // The point of the row under the pointer stays under the pointer.
            let anchor = min(max(CGFloat(x), base[0].minX), base[3].maxX)
            if CGFloat(x) <= base[0].minX { XCTAssertEqual(result[0].minX, base[0].minX, accuracy: 0.001, "Left of the row, its start stays put") }
            if CGFloat(x) >= base[3].maxX { XCTAssertEqual(result[3].maxX, base[3].maxX, accuracy: 0.001, "Right of the row, its end stays put") }
            if let hovered = base.indices.first(where: { base[$0].minX <= anchor && anchor <= base[$0].maxX }) {
                let fraction = (anchor - base[hovered].minX) / base[hovered].width
                XCTAssertEqual(result[hovered].minX + fraction * result[hovered].width, anchor, accuracy: 0.001)
            }
        }
    }

    func testRowStaysContinuousAndWidgetsKeepSizeDuringRapidDirectionChanges() {
        for flags in [[true], [false, true, false], [true, true, true, true],
                      [false, true, true, false, true, true, true, false], [false, false]] {
            var cursor: CGFloat = 16
            let base = flags.map { app -> CGRect in
                let frame = CGRect(x: cursor, y: 6, width: app ? 62 : 126, height: app ? 62 : 72)
                cursor = frame.maxX + 12
                return frame
            }
            var previous = base
            for x in stride(from: -120.0, through: Double(cursor + 120), by: 5) {
                for pointer in [CGFloat(x), cursor - CGFloat(x)] {
                    let result = NativeDockWave.layout(base: base, magnifiable: flags,
                        pointerX: pointer, pointerY: 35)
                    // The hovered icon stays under the pointer.
                    if let hovered = base.indices.first(where: { base[$0].minX <= pointer && pointer <= base[$0].maxX }) {
                        XCTAssertTrue(result[hovered].minX - 0.001 <= pointer && pointer <= result[hovered].maxX + 0.001)
                    }
                    for index in base.indices {
                        if !flags[index] { XCTAssertEqual(result[index].size, base[index].size) }
                        XCTAssertGreaterThanOrEqual(result[index].width, base[index].width)
                        guard index > 0 else { continue }
                        // Sample intermediate retarget frames as well as endpoints.
                        for progress in [CGFloat(0), 0.25, 0.5, 0.75, 1] {
                            let left = previous[index - 1].maxX * (1 - progress) + result[index - 1].maxX * progress
                            let right = previous[index].minX * (1 - progress) + result[index].minX * progress
                            XCTAssertGreaterThanOrEqual(right - left, 12 - 0.001)
                        }
                    }
                    previous = result
                }
            }
            let idle = NativeDockWave.layout(base: base, magnifiable: flags, pointerX: nil,
                pointerY: nil)
            XCTAssertEqual(idle, base)
        }
    }

    func testClampKeepsMagnifiedRowInsideTheOverlay() {
        let frames = [CGRect(x: -10, y: 0, width: 40, height: 40), CGRect(x: 40, y: 0, width: 40, height: 40)]
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 100)
        let clamped = NativeDockWave.clamp(frames, to: bounds, inset: 8)
        XCTAssertEqual(clamped[0].minX, 8)
        XCTAssertEqual(clamped[1].minX, 58)
        let right = NativeDockWave.clamp(frames.map { $0.offsetBy(dx: 400, dy: 0) }, to: bounds, inset: 8)
        XCTAssertEqual(right[1].maxX, 392)
        XCTAssertEqual(NativeDockWave.clamp([CGRect(x: 100, y: 0, width: 40, height: 40)], to: bounds, inset: 8).first?.minX, 100)
    }

    @MainActor
    func testDragGapOpensRoomWithoutMovingTheRowEnd() {
        let lengths: [CGFloat] = [67, 126, 67]
        let closed = NativeDockController.rowFrames(lengths: lengths, thickness: 82, vertical: false)
        XCTAssertEqual(closed.map(\.minX), [8, 78, 207])
        XCTAssertEqual(closed[0].size, NSSize(width: 67, height: 70))
        let gap = NativeDockController.rowFrames(lengths: lengths, thickness: 82, vertical: false, gap: (1, 67))
        XCTAssertEqual(gap[0], closed[0])
        XCTAssertEqual(gap[1].minX, closed[1].minX + 70)
        XCTAssertEqual(gap[2].minX, closed[2].minX + 70)
        let end = NativeDockController.rowFrames(lengths: lengths, thickness: 82, vertical: false, gap: (3, 67))
        XCTAssertEqual(end, closed, "A gap after the last item moves nothing")
        let vertical = NativeDockController.rowFrames(lengths: [67, 67], thickness: 84, vertical: true, gap: (0, 76))
        XCTAssertEqual(vertical[0].minY, 8 + 79)
        XCTAssertEqual(vertical[0].width, 72)
    }

    @MainActor
    func testLaunchBounceStartsStopsAndSurvivesArtworkReset() throws {
        try XCTSkipIf(NativeMotion.reducesMotion, "No bounce under Reduce Motion.")
        let app = NativeApplications.item(for: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"))
        let tile = NativeDockItemView(item: app, iconSize: 60, vertical: false)
        tile.frame = NSRect(x: 0, y: 0, width: 67, height: 70)
        tile.layoutSubtreeIfNeeded()
        XCTAssertNil(tile.animationView.layer?.animation(forKey: "dockLaunchBounce"))
        tile.beginLaunchBounce()
        XCTAssertTrue(tile.isLaunching)
        XCTAssertNotNil(tile.animationView.layer?.animation(forKey: "dockLaunchBounce"))
        tile.resetArtwork()
        XCTAssertNotNil(tile.animationView.layer?.animation(forKey: "dockLaunchBounce"), "Magnification teardown must not end a launch early")
        tile.endLaunchBounce()
        XCTAssertFalse(tile.isLaunching)
        XCTAssertNil(tile.animationView.layer?.animation(forKey: "dockLaunchBounce"))
        tile.resetArtwork()
        XCTAssertNil(tile.animationView.layer?.animation(forKey: "dockLaunchBounce"))
    }

    @MainActor
    func testWidgetTileUsesContinuousCornersMatchingIconRadius() {
        let widget = NativeDockItemView(item: .widget(.clock), iconSize: 60, vertical: false)
        XCTAssertEqual(widget.cornerRadius, 13)
        func layers(in view: NSView) -> [CALayer] { [view.layer].compactMap { $0 } + view.subviews.flatMap { layers(in: $0) } }
        XCTAssertTrue(layers(in: widget).contains { $0.cornerCurve == .continuous && $0.cornerRadius == 13 })
        var folder = DockItem(kind: .folder, title: "Tools", symbol: "folder")
        folder.children = []
        let tile = NativeDockItemView(item: folder, iconSize: 60, vertical: false)
        XCTAssertTrue(layers(in: tile.animationView).contains { $0.cornerCurve == .continuous && $0.cornerRadius == 13 })
        if #available(macOS 26.0, *) {
            XCTAssertFalse(layers(in: tile).isEmpty)
            func views(in view: NSView) -> [NSView] { [view] + view.subviews.flatMap { views(in: $0) } }
            XCTAssertFalse(views(in: tile).contains { $0 is NSGlassEffectView }, "Folder tiles no longer nest glass inside the shelf")
        }
    }

    func testLiftedIconHitAreaIncludesItsVisibleArtworkAndOriginalBaseline() {
        let artwork = CGRect(x: 30, y: 22, width: 70, height: 70)
        let hit = NativeDockWave.hitRect(artwork: artwork, tileWidth: 76)
        XCTAssertTrue(hit.contains(artwork))
        XCTAssertTrue(hit.contains(CGPoint(x: artwork.midX, y: 2)))
        XCTAssertFalse(hit.contains(CGPoint(x: artwork.midX, y: artwork.maxY + 10)))
    }
}
#endif
