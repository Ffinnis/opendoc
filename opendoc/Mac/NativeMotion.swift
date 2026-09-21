#if os(macOS)
import AppKit
import QuartzCore

@MainActor
enum NativeMotion {
    static var reducesMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || CommandLine.arguments.contains("--reduce-motion")
    }

    static func animate(_ duration: TimeInterval, timingFunction: CAMediaTimingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.8, 0.3, 1), changes: () -> Void, completion: @escaping () -> Void = {}) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reducesMotion ? 0 : duration
            context.timingFunction = timingFunction
            changes()
        } completionHandler: { completion() }
    }
}
#endif
