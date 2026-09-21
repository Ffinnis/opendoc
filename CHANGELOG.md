# Changelog

## Unreleased

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
