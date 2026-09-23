# Changelog

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
