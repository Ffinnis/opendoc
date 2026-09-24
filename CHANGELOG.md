# Changelog

## 1.3.1

- Automatically reduce icon size when a crowded bottom or side dock exceeds the available screen space, including docks with 30 or more apps. Keep the saved size preference and restore it when space allows.
- Preserve widget dimensions and keep hover magnification, click targets, and drag positioning aligned with the fitted icons.
- Show scrollbars when a dock still overflows at the minimum icon size, and recalculate the layout when displays change.

## 1.3.0

- Magnify the dock like the system Dock. Icons near the pointer grow, the row makes room for them, and the shelf widens around it. The icon under the pointer stays under the pointer.
- Bounce an app's icon while it launches, and show the system poof when an item is removed from the dock.
- Open a gap for a dragged item as you move it along the dock. The item settles into its new place or into the folder it joins.
- Keep the dock's shadow while it is magnified, and keep magnified icons sharp.
- Use the same continuous corners for widgets, folders, and app icons. Folders use a flat tile instead of glass layered on the dock's glass.
- Follow light and dark appearance on macOS versions before Tahoe, with a thin edge highlight on the shelf.
- Show item names beside side docks and when Reduce Motion is on, without enlarging icons.
- Show the dock's settings button only while the pointer is over the dock.

## 1.2.0

- Create programmable dock widgets using Bash, Node.js, or another local executable. Commands return JSON for the widget's value, detail, and progress bar.
- Start with Codex and Claude usage presets powered by an installed CodexBar helper.
- Configure command arguments, refresh intervals, and timeouts in the native widget editor or through the Open Doc CLI. Local execution stays disabled until enabled for the widget.
- Keep the last successful reading when a command fails, with an error shown in the widget. Command execution runs in the background with time and output limits.

## 1.1.4

- Include the Open Doc app icon in macOS installations, with standard and Retina sizes.
- Keep the landing page and automatic update feed together when deploying either one.

## 1.1.3

- App menus inside folders now include Open, Show in Finder, Hide or Show, and Quit. New Window appears when supported. Menus refresh their running state when opened.
- Bring an app's windows forward together when clicked in the dock or a folder, including windows on another display.

## 1.1.2

- Reopen running applications through Launch Services so Finder can show a window after its last window was closed.
- Detect New Window support from each application's scripting dictionary and show the action in dock and folder menus. Detection is cached until the dictionary changes. macOS asks for Automation permission on first use.

## 1.1.1

- Switch directly between dock folders with one click. Clicking the open folder again closes it.
- Expanded folders use three columns for five or more apps, with up to nine apps per page. Page buttons and horizontal gestures navigate larger folders without resizing the window.
- Folder previews show up to nine icons. Larger folders show eight icons and the number of remaining apps.
- Show one running indicator per open app inside a folder.
- Use a neutral focus highlight in folder tiles, wrap long app names, and avoid duplicate tooltips over short names.
- Keep folder glass and app artwork together during magnification and allow icons to rise above the dock shelf without clipping.
- Animate artwork without resizing its native glass content on every pointer move.
- Verify signed Sparkle updates before extraction.
