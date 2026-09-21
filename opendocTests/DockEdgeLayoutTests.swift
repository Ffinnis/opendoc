#if os(macOS)
import XCTest
import AppKit
import QuartzCore
@testable import opendoc

final class DockEdgeLayoutTests: XCTestCase {
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
