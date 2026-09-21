# Open Doc

An open-source desktop dock with application folders, configurable widgets, and multiple independent docks. MIT licensed. Updates use the open-source Sparkle framework.

The Mac app uses AppKit for borderless desktop panels, native menus, settings, and file pickers. macOS 26 uses NSGlassEffectView; macOS 14 and 15 use NSVisualEffectView. No SwiftUI. Widget controls are native; an offscreen WebKit instance parses downloaded HTML for custom widgets.

Inspired by [Dockset's public screenshots](https://dockset.app/). Dockset was not installed or reverse engineered. No Dockset code, branding, screenshots, or assets are distributed. Application icons come from applications already installed on your Mac.

## Run

Open `opendoc.xcodeproj` in Xcode 26 or later. Select the `opendoc` scheme and **My Mac**.

```sh
xcodebuild -project opendoc.xcodeproj -scheme opendoc \
  -configuration Release -destination 'platform=macOS' -derivedDataPath build/mac \
  CODE_SIGNING_ALLOWED=NO build
open build/mac/Build/Products/Release/opendoc.app
```

The Mac app runs in the menu bar. On its first launch, it imports pinned applications from Apple's Dock and opens a Desktop dock with a focus timer, calendar, clock, and Trash. It also shows running applications. Clicking an application launches it or activates its windows.

## Updates

Installed copies check for updates daily and download signed updates through Sparkle. Use **Check for Updates…** in the Open Doc menu or menu bar icon. Disable **Automatically Check for Updates** to check manually. Development builds outside Applications and isolated test sessions do not start the updater.

Downloads are hosted in [GitHub Releases](https://github.com/Ffinnis/opendoc/releases). The update feed is deployed by GitHub Actions only after validating the archive signature and notarization. See [the release guide](docs/Releasing.md).

## Desktop controls

Agents can inspect and edit the running Mac app through a [local JSON CLI](Examples/Agent-CLI.md). The app installs `opendoc` on first launch from Applications. Run `opendoc schema` for operations and `opendoc state` for IDs. Widget changes and dock appearance updates apply live through the same validation and undo path as Settings. No computer use is required.

Run `opendoc help widget.add` or `opendoc widget.add --help` for required fields and examples. `opendoc help --json` returns structured documentation without connecting to the app.

- Click the settings icon at the end of a dock to add applications, files, folders, links, spacers, or widgets.
- Drag items within a dock to reorder them. Dragging a running app to a saved position pins it, including across separators. The blue insertion marker shows the destination. You can also reorder the native list in Settings.
- Hold a dragged application over another application's center to create a folder, or drop it onto an existing folder. In Settings, select two or more applications and choose **Group Applications**. Open a folder to launch its apps, rename it, or add more apps. Right-click a contained app to move it back to the dock. **Ungroup** restores all apps without deleting their shortcuts. Folder apps appear only inside that folder. A dot below a folder means one of its apps is running; open the folder to see each app's running dot.
- Open **Widget Library** to search, filter, and preview widgets before adding them to the selected dock.
- Right-click an application to quit it, remove a pinned shortcut, or keep a running application in the dock.
- Click a widget to open its editor in a native popover anchored to the widget.
- Choose **New Dock** to add another dock. Each profile has its own items, position, size, material, and auto-hide setting. Docks on the same edge are offset so they remain accessible.
- Use the menu bar icon to show or hide docks, open Settings, restore Apple's Dock, or quit.
- Import or export JSON backups using **More** in the Settings toolbar. Imports add independent copies without replacing existing profiles.
- Use **Edit → Undo Dock Edit** or **Redo Dock Edit** to recover recent changes, including removal of an entire folder. In Settings, **⌘Z / ⇧⌘Z** undo and redo dock edits; when typing, they use the text field's history. **⌘W** closes the current window. History lasts for the current app session.

Bottom-dock icons lift and enlarge within their app group's available spacing. Widgets, settings, and the glass bar stay anchored. Cached artwork animates through Core Animation, with hit targets following the visible icons. Side docks have a smaller hover response. Reduce Motion is respected.

New docks auto-hide by default. Hidden docks reveal after 280 ms of continuous hover within an eight-point strip at their screen edge, along the dock's length. Leaving that strip cancels the pending reveal. The larger visible area and the gap to the edge keep the dock open after revealing. Auto-hide pauses during menus, dragging, and folder or widget popovers. Widget drawing is throttled to the cadence of its data and suspended while hidden.

## Replacing Apple's Dock

Replacement is enabled on the first Mac launch. Open Doc saves the original `autohide` and `autohide-delay` preferences, hides Apple's Dock, and restores those preferences when you quit or turn replacement off. Hiding the last Open Doc dock temporarily restores Apple's Dock; showing a dock again resumes replacement without changing your preference. Apple's pinned items are never changed. Its process continues to provide system functions such as Mission Control.

A separate recovery process watches Open Doc and restores the saved preferences after an unexpected exit. The original values are stored in `~/Library/Application Support/OpenDoc/system-dock-session.json`. Both normal quit and forced termination have been checked locally. If the Mac loses power, launch Open Doc again to recover the stale session.

Open Doc does not reserve desktop space, manage other applications' windows, provide Dock window previews, or implement every macOS Dock feature. It is an early implementation, not a complete Dockset replacement. No login item is installed automatically.

## Widgets

Built-in widgets include clocks, calendar dates, focus and stopwatch timers, notes, checklists, hydration, countdowns, battery, CPU, and memory. Web value widgets read a field from an HTTPS JSON endpoint.

Custom widgets support persistent numeric state, JavaScript formatting, progress, and up to four buttons. They can extract text or attributes from static HTML using CSS selectors. See [the widget guide](docs/Widgets.md) and [USD/RUB example](Examples/USD-RUB.md).

## Data

The Mac archive is `~/Library/Application Support/OpenDoc/workspace.json`. Writes are atomic, imports are validated, and unreadable archives are preserved. File bookmarks are device-specific. There are no analytics. Network requests are used for update checks and downloads, web widgets you configure, and links you open. Sparkle system profiling is disabled. Do not put secrets in endpoint URLs: widget configuration is stored as plain JSON.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) for build commands, isolated development sessions, validation, and pull-request guidance. Coding agents should also read [AGENTS.md](AGENTS.md).

The project uses the [MIT license](LICENSE). App icons are read from the local installation and remain the property of their respective owners.

## Validation status

Mac builds and Mac unit tests have been checked locally. The GitHub workflow runs Mac unit tests and checks CLI help. UI interaction and sustained 120 fps require separate desktop checks.
