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

    /// Explicit animations also work on the first frame of a newly attached layer.
    /// Retarget from presentation values so rapid pointer movement cannot jump.
    static var timingFunction: CAMediaTimingFunction { CAMediaTimingFunction(controlPoints: 0.22, 0.65, 0.3, 1) }

    static func move(_ layer: CALayer, to frame: CGRect, duration: TimeInterval) {
        move(layer, to: frame, duration: duration) { layer.frame = $0 }
    }

    /// Capture the displayed geometry before AppKit updates the material's model
    /// frame. Glass and artwork then share the same explicit animation transaction.
    static func move(_ view: NSView, to frame: CGRect, duration: TimeInterval) {
        view.wantsLayer = true
        guard let layer = view.layer else { return }
        move(layer, to: frame, duration: duration) { view.frame = $0 }
    }

    private static func move(_ layer: CALayer, to frame: CGRect, duration: TimeInterval,
                             updateFrame: (CGRect) -> Void) {
        guard layer.frame != frame || duration == 0 else { return }
        let presentation = layer.presentation()
        let fromPosition = presentation?.position
            ?? (layer.animation(forKey: "wavePosition") as? CABasicAnimation)?.fromValue as? CGPoint
            ?? layer.position
        let fromBounds = presentation?.bounds
            ?? (layer.animation(forKey: "waveBounds") as? CABasicAnimation)?.fromValue as? CGRect
            ?? layer.bounds
        CATransaction.begin(); CATransaction.setDisableActions(true)
        updateFrame(frame)
        if duration > 0 {
            for (key, from, to) in [("position", NSValue(point: fromPosition), NSValue(point: layer.position)),
                                    ("bounds", NSValue(rect: fromBounds), NSValue(rect: layer.bounds))] {
                let animation = CABasicAnimation(keyPath: key)
                animation.fromValue = from; animation.toValue = to
                animation.duration = duration
                animation.timingFunction = timingFunction
                layer.add(animation, forKey: key == "position" ? "wavePosition" : "waveBounds")
            }
        } else {
            layer.removeAnimation(forKey: "wavePosition")
            layer.removeAnimation(forKey: "waveBounds")
        }
        CATransaction.commit()
    }
}
#endif
