#if os(macOS)
import AppKit
import QuartzCore

/// Lifts app artwork inside fixed groups while keeping widgets anchored.
enum NativeDockWave {
    static let entryDuration: TimeInterval = 0.16
    static let trackingDuration: TimeInterval = 0.085
    static let exitDuration: TimeInterval = 0.16

    static func overlayFrame(parent: CGRect, screen: CGRect) -> CGRect {
        let width = min(screen.width, parent.width + 240)
        return CGRect(x: min(max(screen.minX, parent.minX - 120), screen.maxX - width),
                      y: parent.minY, width: width, height: parent.height + 120)
    }

    /// Widgets and the shelf are anchors. Each uninterrupted app group uses its
    /// own inter-icon space for magnification, without pushing a widget or moving
    /// the shelf edges. In tight groups, lift supplies feedback without overlap.
    static func layout(base: [CGRect], magnifiable: [Bool], pointerX: CGFloat?, pointerY: CGFloat?) -> [CGRect] {
        guard base.count == magnifiable.count, let x = pointerX else {
            return base
        }
        let growth = base.indices.map { index -> CGFloat in
            guard magnifiable[index] else { return 0 }
            let rect = base[index]
            let verticalDistance = pointerY.map { max(0, rect.minY - $0, $0 - rect.maxY) } ?? 0
            let distance = min(1, hypot(x - rect.midX, verticalDistance) / 120)
            return rect.width * 0.5 * (1 + cos(distance * .pi)) / 2
        }
        var items = base
        var start = 0
        while start < base.count {
            guard magnifiable[start] else { start += 1; continue }
            var end = start + 1
            while end < base.count, magnifiable[end] { end += 1 }
            let group = start..<end
            // Keep at least four points of the existing gaps. A small group can
            // still lift naturally even when there is no room to grow sideways.
            let capacity = group.dropLast().map { max(0, base[$0 + 1].minX - base[$0].maxX - 4) }
            let room = capacity.reduce(0, +)
            let requested = group.reduce(CGFloat.zero) { $0 + growth[$1] }
            let scale = requested > 0 ? min(1, room / requested) : 0
            let used = requested * scale
            var cursor = base[start].minX
            for index in group {
                let extra = growth[index] * scale
                let influence = growth[index] / max(1, base[index].width) * 2
                items[index] = CGRect(x: cursor, y: base[index].minY + influence * 14,
                    width: base[index].width + extra,
                    height: base[index].height * (1 + extra / max(1, base[index].width)))
                cursor = items[index].maxX
                if index + 1 < end {
                    let gap = base[index + 1].minX - base[index].maxX
                    cursor += gap - (room > 0 ? capacity[index - start] * used / room : 0)
                }
            }
            start = end
        }
        return items
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

    static var timingFunction: CAMediaTimingFunction { CAMediaTimingFunction(controlPoints: 0.22, 0.65, 0.3, 1) }
}
#endif
