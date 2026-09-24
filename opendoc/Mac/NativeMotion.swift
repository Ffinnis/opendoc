#if os(macOS)
import AppKit
import QuartzCore

@MainActor
enum NativeMotion {
    static var reducesMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || CommandLine.arguments.contains("--reduce-motion")
    }

    /// Every dock transition uses one of two curves: `standard` for things that
    /// move once (reveal, reflow, fades), `tracking` for magnification, which
    /// retargets on each pointer event and must start at full speed.
    nonisolated static var standard: CAMediaTimingFunction { CAMediaTimingFunction(controlPoints: 0.22, 0.8, 0.3, 1) }
    nonisolated static var tracking: CAMediaTimingFunction { CAMediaTimingFunction(controlPoints: 0.22, 0.65, 0.3, 1) }

    static func animate(_ duration: TimeInterval, timingFunction: CAMediaTimingFunction = standard, changes: () -> Void, completion: @escaping () -> Void = {}) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reducesMotion ? 0 : duration
            context.timingFunction = timingFunction
            changes()
        } completionHandler: { completion() }
    }

    /// An interruptible spring. `duration` is the perceptual duration, so a
    /// retarget mid-flight continues from the presentation value without a
    /// visible restart. Bounce 0 is critically damped.
    nonisolated static func spring(_ keyPath: String, duration: TimeInterval, bounce: CGFloat = 0) -> CASpringAnimation {
        let animation = CASpringAnimation(perceptualDuration: duration, bounce: bounce)
        animation.keyPath = keyPath
        animation.duration = animation.settlingDuration
        return animation
    }

    /// Time until a spring with this perceptual duration comes to rest.
    nonisolated static func settlingDuration(_ duration: TimeInterval, bounce: CGFloat = 0) -> TimeInterval {
        CASpringAnimation(perceptualDuration: duration, bounce: bounce).settlingDuration
    }
}
#endif
