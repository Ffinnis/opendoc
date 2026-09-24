#if os(macOS)
import AppKit
import QuartzCore

/// Magnifies app artwork the way the system Dock does: icons near the pointer
/// grow, the row spreads out to make room, and the shelf widens around it.
enum NativeDockWave {
    /// Pointer tracking retargets on every mouse event. Short ease-out curves
    /// start at full speed from the visible position, so icons follow the
    /// pointer without the start-from-rest lag a retargeted spring has.
    static let entryDuration: TimeInterval = 0.16
    static let trackingDuration: TimeInterval = 0.085
    static let exitDuration: TimeInterval = 0.18
    /// The largest icon is this much wider than at rest.
    static let maximumGrowth: CGFloat = 0.3
    /// Distance from the pointer over which magnification fades to zero.
    static let reach: CGFloat = 120

    static func overlayFrame(parent: CGRect, screen: CGRect) -> CGRect {
        let width = min(screen.width, parent.width + 240)
        return CGRect(x: min(max(screen.minX, parent.minX - 120), screen.maxX - width),
                      y: parent.minY, width: width, height: parent.height + 120)
    }

    /// Widgets keep their size but slide with the row. Every icon grows by a
    /// cosine falloff of its distance to the pointer and the gaps between items
    /// are preserved. Like the system Dock, the point of the row under the
    /// pointer stays under it, so the row grows on both sides of the pointer
    /// and the hovered icon never drifts away. Beyond either end of the row,
    /// that end stays put.
    static func layout(base: [CGRect], magnifiable: [Bool], pointerX: CGFloat?, pointerY: CGFloat?, maximumWidth: CGFloat? = nil) -> [CGRect] {
        guard base.count == magnifiable.count, let x = pointerX, !base.isEmpty else {
            return base
        }
        let growth = base.indices.map { index -> CGFloat in
            guard magnifiable[index] else { return 0 }
            let rect = base[index]
            let verticalDistance = pointerY.map { max(0, rect.minY - $0, $0 - rect.maxY) } ?? 0
            let distance = min(1, hypot(x - rect.midX, verticalDistance) / reach)
            return rect.width * maximumGrowth * (1 + cos(distance * .pi)) / 2
        }
        guard growth.contains(where: { $0 > 0 }) else { return base }
        // A crowded row may have less room than the full wave needs. Limit
        // growth before positioning; translation alone cannot fit a wider row.
        let baseWidth = base[base.count - 1].maxX - base[0].minX
        let growthScale = maximumWidth.map { min(1, max(0, $0 - baseWidth) / growth.reduce(0, +)) } ?? 1
        var items = base
        var cursor = base[0].minX
        for index in base.indices {
            let rect = base[index]
            let extra = growth[index] * growthScale
            items[index] = CGRect(x: cursor, y: rect.minY, width: rect.width + extra,
                                  height: rect.height + extra * rect.height / max(1, rect.width))
            cursor = items[index].maxX
            if index + 1 < base.count { cursor += base[index + 1].minX - rect.maxX }
        }
        let shift = x - magnifiedPosition(of: x, base: base, magnified: items)
        return items.map { $0.offsetBy(dx: shift, dy: 0) }
    }

    /// Where a resting x coordinate lands in an unshifted magnified row. Items
    /// scale their interior; gaps keep their width.
    static func magnifiedPosition(of x: CGFloat, base: [CGRect], magnified: [CGRect]) -> CGFloat {
        let s = min(max(x, base[0].minX), base[base.count - 1].maxX)
        for index in base.indices {
            let rect = base[index]
            if s <= rect.maxX {
                if s >= rect.minX {
                    return magnified[index].minX + (s - rect.minX) * magnified[index].width / max(1, rect.width)
                }
                // In the gap before this item.
                return magnified[index].minX - (rect.minX - s)
            }
        }
        return magnified[magnified.count - 1].maxX
    }

    /// Shifts a magnified layout so it stays inside `bounds` at screen edges.
    static func clamp(_ frames: [CGRect], to bounds: CGRect, inset: CGFloat) -> [CGRect] {
        guard let first = frames.first, let last = frames.last else { return frames }
        var shift: CGFloat = 0
        if first.minX < bounds.minX + inset { shift = bounds.minX + inset - first.minX }
        else if last.maxX > bounds.maxX - inset { shift = bounds.maxX - inset - last.maxX }
        guard shift != 0 else { return frames }
        return frames.map { $0.offsetBy(dx: shift, dy: 0) }
    }

    static func hitRect(artwork: CGRect, tileWidth: CGFloat) -> CGRect {
        let width = max(artwork.width, tileWidth)
        return CGRect(x: artwork.midX - width / 2, y: 0, width: width, height: artwork.maxY + 3)
    }

    /// Animate a fixed-size host, not the effect view's frame. Its native glass
    /// mask and image layout remain unchanged while the compositor scales both.
    static func transform(_ layer: CALayer, from base: CGRect, to target: CGRect, duration: TimeInterval) {
        guard base.width > 0, base.height > 0 else { return }
        let scaleX = target.width / base.width
        let scaleY = target.height / base.height
        let transform = CATransform3DMakeAffineTransform(CGAffineTransform(
            a: scaleX, b: 0, c: 0, d: scaleY,
            tx: target.minX - base.minX + (scaleX - 1) * base.width * layer.anchorPoint.x,
            ty: target.minY - base.minY + (scaleY - 1) * base.height * layer.anchorPoint.y))
        guard !CATransform3DEqualToTransform(layer.transform, transform) || duration == 0 else { return }
        let previous = layer.presentation()?.transform
            ?? ((layer.animation(forKey: "dockArtworkTransform") as? CABasicAnimation)?.fromValue as? NSValue)?.caTransform3DValue
            ?? layer.transform
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = transform
        if duration > 0 {
            let animation = CABasicAnimation(keyPath: "transform")
            animation.fromValue = NSValue(caTransform3D: previous)
            animation.toValue = NSValue(caTransform3D: transform)
            animation.duration = duration
            animation.timingFunction = timingFunction
            layer.add(animation, forKey: "dockArtworkTransform")
        } else {
            layer.removeAnimation(forKey: "dockArtworkTransform")
        }
        CATransaction.commit()
    }

    static var timingFunction: CAMediaTimingFunction { NativeMotion.tracking }
}
#endif
