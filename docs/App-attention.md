# App badges and attention

Proposal, September 2026. Badge mirroring and attention animations are not implemented yet.

Open Doc hides Apple's Dock using `SystemDockSession`; the system Dock still runs. Apps continue sending their attention requests there. `NativeDockController` observes application lifecycle events, and `NativeDockItemView` displays running indicators, but neither observes badges or attention requests.

## What macOS exposes

- [`NSApplication.requestUserAttention`](https://developer.apple.com/documentation/appkit/nsapplication/requestuserattention(_:)) requests attention for the calling app. An informational request bounces briefly; a critical request continues until activation or cancellation. Overriding it in Open Doc would only affect Open Doc's requests.
- [`NSWorkspace`](https://developer.apple.com/documentation/appkit/nsworkspace) provides application lifecycle notifications. Its documented notifications do not include a system-wide stream of attention requests.
- [`UNUserNotificationCenter.getDeliveredNotifications`](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/getdeliverednotifications(completionhandler:)) returns the caller's notifications. It cannot supply other apps' unread counts or notifications.
- The installed macOS accessibility definitions at `/System/Library/Accessibility/AccessibilityDefinitions.plist` include `AXStatusLabel` on Dock items and mark it private. This is a candidate source for badge text through Accessibility, requiring user permission, but it is not a stable public contract. Availability while the Dock is hidden, change notifications, and behavior across macOS versions still need a prototype. A badge change is not proof that the app requested a bounce.

Exact native bounce mirroring is unresolved. Do not promise it based on badge support alone. Apps can request attention without changing a badge, and badges can change without a notification.

## Recommended first version

Start with an opt-in "Show app badges" setting. Explain the Accessibility permission when the user enables it. Mirror available badge text on application icons, including nonnumeric values. Keep Notification Center banners and sounds under macOS control.

Add a separate "Animate badge increases" setting after the badge source works reliably. Animate once when a numeric badge increases or a previously empty badge appears. Establish a baseline on startup, permission recovery, and Dock restart without animating existing unread items. Do not replay unchanged badges or animate decreases. Use a static highlight with Reduce Motion enabled.

Keep the badge until its source changes. App activation clears Open Doc's attention highlight, not the app's unread count. A folder can show a dot when any child has a badge; its popover should show each child's actual label. Mirror state across visible profiles without inserting apps into saved profiles. Do not reveal an auto-hidden dock for badge updates in the first version.

## Implementation approach

1. Prototype reading Dock application items and badge labels in a disposable macOS account. Match by application URL and bundle identity, not localized display names. Verify hidden Dock behavior and permission revocation before building the UI.
2. Use one shared monitor, owned by `MacApplication`, with cached state per application. Prefer Accessibility change notifications if the Dock supports them; otherwise evaluate a bounded, low-frequency refresh. Put cross-process reads on a worker with a messaging timeout. Reconnect after Dock restarts and stop when disabled or no docks are visible.
3. Publish only changed values to `NativeDockItemView`. Keep transient badges and attention state out of `DockStore`. Persist user settings through `DockStore`, preserving validation, undo, and profile targeting; update CLI help, schema, and validation together if the settings are exposed there.
4. Attach badge artwork to the icon so magnification carries it along. Use a separate inner view for attention motion because `NativeDockMagnification` already controls the artwork transform. Hit testing must follow the visible icon. Pointer handling must never query Accessibility or rebuild the dock.

Do not disable Apple's bouncing until there is a dependable replacement signal. If a future option changes a Dock preference, extend the existing ownership snapshot and restoration logic for quit, replacement disable, last-dock close, and crash recovery.

## Acceptance checks

Test baseline loading, increases, decreases, text badges, duplicate app names, permission denial and revocation, Dock restart, and app termination. Unsupported or timed-out reads must not produce false attention events.

Use an isolated store for state tests. Visually check badges and click targets at both ends of bottom and side docks, during magnification, rapid pointer changes, dragging, folder opening, auto-hide, and Reduce Motion. Exercise actual Dock replacement only in a disposable account or machine. Measure idle polling and interaction cost separately from visual checks.
