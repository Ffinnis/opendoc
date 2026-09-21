#if os(macOS)
import XCTest
import AppKit
import QuartzCore
@testable import opendoc

final class DockEdgeLayoutTests: XCTestCase {
    @MainActor
    func testFolderGlassAndArtworkShareAnimationGeometryWhenRetargeted() throws {
        let initial = CGRect(x: 70, y: 8, width: 62, height: 62)
        let glass = DockGlassRoot.makeFolderMaterial(containing: NSView())
        let artwork = CALayer()
        NativeDockWave.move(glass, to: initial, duration: 0)
        NativeDockWave.move(artwork, to: initial, duration: 0)
        let glassLayer = try XCTUnwrap(glass.layer)
        for frame in [CGRect(x: 62, y: 22, width: 75, height: 75),
                      CGRect(x: 80, y: 12, width: 65, height: 65), initial] {
            NativeDockWave.move(glass, to: frame, duration: 0.085)
            NativeDockWave.move(artwork, to: frame, duration: 0.085)
            XCTAssertEqual(glass.frame, frame)
            XCTAssertEqual(artwork.frame, frame)
            for key in ["wavePosition", "waveBounds"] {
                let materialAnimation = try XCTUnwrap(glassLayer.animation(forKey: key) as? CABasicAnimation)
                let artworkAnimation = try XCTUnwrap(artwork.animation(forKey: key) as? CABasicAnimation)
                XCTAssertEqual(materialAnimation.duration, artworkAnimation.duration)
                for control in 0...3 {
                    var materialPoint: [Float] = [0, 0]
                    var artworkPoint: [Float] = [0, 0]
                    materialAnimation.timingFunction?.getControlPoint(at: control, values: &materialPoint)
                    artworkAnimation.timingFunction?.getControlPoint(at: control, values: &artworkPoint)
                    XCTAssertEqual(materialPoint, artworkPoint)
                }
            }
            // AppKit anchors view-backed layers at zero; raw artwork is centered.
            // Compare the displayed rectangles, not their different layer positions.
            func animatedFrame(_ layer: CALayer, progress: CGFloat) throws -> CGRect {
                let position = try XCTUnwrap(layer.animation(forKey: "wavePosition") as? CABasicAnimation)
                let bounds = try XCTUnwrap(layer.animation(forKey: "waveBounds") as? CABasicAnimation)
                let from = try XCTUnwrap(position.fromValue as? NSValue).pointValue
                let to = try XCTUnwrap(position.toValue as? NSValue).pointValue
                let fromSize = try XCTUnwrap(bounds.fromValue as? NSValue).rectValue.size
                let toSize = try XCTUnwrap(bounds.toValue as? NSValue).rectValue.size
                let width = fromSize.width + (toSize.width - fromSize.width) * progress
                let height = fromSize.height + (toSize.height - fromSize.height) * progress
                return CGRect(x: from.x + (to.x - from.x) * progress - width * layer.anchorPoint.x,
                              y: from.y + (to.y - from.y) * progress - height * layer.anchorPoint.y,
                              width: width, height: height)
            }
            for progress: CGFloat in [0, 0.25, 0.5, 0.75, 1] {
                XCTAssertEqual(try animatedFrame(glassLayer, progress: progress),
                               try animatedFrame(artwork, progress: progress))
            }
        }
        // Reduce Motion must finish an in-flight animation even at the same target.
        NativeDockWave.move(glass, to: initial, duration: 0)
        NativeDockWave.move(artwork, to: initial, duration: 0)
        XCTAssertNil(glassLayer.animation(forKey: "wavePosition"))
        XCTAssertNil(artwork.animation(forKey: "wavePosition"))
        XCTAssertNil(glassLayer.animation(forKey: "waveBounds"))
        XCTAssertNil(artwork.animation(forKey: "waveBounds"))
    }

    @MainActor
    func testFolderMaterialTracksRenderedArtworkDuringLiveRetargeting() async throws {
        let window = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 260, height: 160),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let root = try XCTUnwrap(window.contentView)
        root.wantsLayer = true
        let glass = DockGlassRoot.makeFolderMaterial(containing: NSView())
        root.addSubview(glass)
        let artwork = CALayer()
        root.layer?.addSublayer(artwork)
        let initial = CGRect(x: 70, y: 8, width: 62, height: 62)
        NativeDockWave.move(glass, to: initial, duration: 0)
        NativeDockWave.move(artwork, to: initial, duration: 0)
        window.orderBack(nil)
        root.layoutSubtreeIfNeeded()
        CATransaction.flush()
        try await Task.sleep(for: .milliseconds(30))
        for target in [CGRect(x: 62, y: 22, width: 75, height: 75),
                       CGRect(x: 80, y: 12, width: 65, height: 65), initial] {
            CATransaction.begin()
            NativeDockWave.move(glass, to: target, duration: 0.16)
            NativeDockWave.move(artwork, to: target, duration: 0.16)
            CATransaction.commit()
            CATransaction.flush()
            for _ in 0..<3 {
                try await Task.sleep(for: .milliseconds(20))
                let materialFrame = try XCTUnwrap(glass.layer?.presentation()).frame
                let artworkFrame = try XCTUnwrap(artwork.presentation()).frame
                XCTAssertEqual(materialFrame.minX, artworkFrame.minX, accuracy: 0.5)
                XCTAssertEqual(materialFrame.minY, artworkFrame.minY, accuracy: 0.5)
                XCTAssertEqual(materialFrame.width, artworkFrame.width, accuracy: 0.5)
                XCTAssertEqual(materialFrame.height, artworkFrame.height, accuracy: 0.5)
            }
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
