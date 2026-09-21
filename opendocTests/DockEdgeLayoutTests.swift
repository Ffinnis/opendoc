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

    func testEdgeWidgetsAndShelfStayStationaryDuringHover() {
        let base = [CGRect(x: 128, y: 6, width: 126, height: 72),
                    CGRect(x: 260, y: 9, width: 62, height: 62),
                    CGRect(x: 332, y: 9, width: 62, height: 62),
                    CGRect(x: 404, y: 6, width: 126, height: 72)]
        let bar = CGRect(x: 120, y: 0, width: 454, height: 84)
        let settings = CGRect(x: 540, y: 10, width: 25, height: 64)
        for x in stride(from: 100.0, through: 580, by: 2) {
            let result = NativeDockWave.layout(base: base, magnifiable: [false, true, true, false], pointerX: x,
                                               pointerY: 35)
            XCTAssertTrue(bar.contains(result[0]))
            XCTAssertTrue(bar.contains(result[3]))
            XCTAssertEqual(result[0], base[0])
            XCTAssertEqual(result[3], base[3])
            for i in 1..<base.count {
                XCTAssertGreaterThanOrEqual(result[i].minX - result[i - 1].maxX, 4 - 0.001)
            }
            XCTAssertEqual(result[1].minX, base[1].minX, accuracy: 0.001)
            XCTAssertEqual(result[2].maxX, base[2].maxX, accuracy: 0.001)
            XCTAssertEqual(settings.minX - result[3].maxX, settings.minX - base[3].maxX, accuracy: 0.001)
        }
    }

    func testAppGroupsDoNotPushWidgetsOrOverlapDuringRapidDirectionChanges() {
        for flags in [[true], [false, true, false], [true, true, true, true],
                      [false, true, true, false, true, true, true, false], [false, false]] {
            var cursor: CGFloat = 16
            let base = flags.map { app -> CGRect in
                let frame = CGRect(x: cursor, y: 6, width: app ? 62 : 126, height: app ? 62 : 72)
                cursor = frame.maxX + 12
                return frame
            }
            let bar = CGRect(x: 8, y: 0, width: cursor + 34, height: 84)
            let settings = CGRect(x: cursor, y: 12, width: 25, height: 60)
            var previous = base
            for x in stride(from: -120.0, through: Double(cursor + 120), by: 5) {
                for pointer in [CGFloat(x), cursor - CGFloat(x)] {
                    let result = NativeDockWave.layout(base: base, magnifiable: flags,
                        pointerX: pointer, pointerY: 35)
                    for index in base.indices {
                        if !flags[index] { XCTAssertEqual(result[index], base[index]) }
                        XCTAssertGreaterThanOrEqual(result[index].width, base[index].width)
                        XCTAssertGreaterThanOrEqual(result[index].minX, bar.minX)
                        XCTAssertLessThanOrEqual(result[index].maxX, settings.minX)
                        guard index > 0 else { continue }
                        // Sample intermediate retarget frames as well as endpoints.
                        for progress in [CGFloat(0), 0.25, 0.5, 0.75, 1] {
                            let left = previous[index - 1].maxX * (1 - progress) + result[index - 1].maxX * progress
                            let right = previous[index].minX * (1 - progress) + result[index].minX * progress
                            XCTAssertGreaterThanOrEqual(right - left, 4 - 0.001)
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

    func testLiftedIconHitAreaIncludesItsVisibleArtworkAndOriginalBaseline() {
        let artwork = CGRect(x: 30, y: 22, width: 70, height: 70)
        let hit = NativeDockWave.hitRect(artwork: artwork, tileWidth: 76)
        XCTAssertTrue(hit.contains(artwork))
        XCTAssertTrue(hit.contains(CGPoint(x: artwork.midX, y: 2)))
        XCTAssertFalse(hit.contains(CGPoint(x: artwork.midX, y: artwork.maxY + 10)))
    }
}
#endif
