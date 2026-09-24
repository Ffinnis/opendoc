# Using Open Doc

Open Doc runs from the menu bar. Use the settings button at the end of a dock to add items, open Settings, or create another dock.

## Arrange your dock

Drag an item to move it. The other items move apart to show where it will land. Drag a running app into the pinned section to keep it there, or right-click it and choose **Keep in Dock**. You can also reorder items in Settings.

Add applications, files, folders, links, spacers, or widgets from the dock's settings menu. Its button appears at the end of the dock while the pointer is over the dock. You can also Control-click the dock's background. Choose **New Dock...** to create another dock with its own items and appearance. In Settings, select the dock you want to edit first.

## Group apps into folders

Hold a dragged app over the center of another app to create a folder. Drop an app onto an existing folder to add it. In Settings, you can also select several apps and choose **Group Applications**.

Click a folder to open it. Click another folder to switch, or click the same folder again to close it. Each page holds up to nine apps. Use the page buttons or a horizontal trackpad gesture to move between pages.

A folder shows one dot for each running app inside it. Apps in that folder no longer appear separately in the same dock. Right-click a contained app to move it back to the dock. **Ungroup** puts all the apps back without deleting their shortcuts.

## Open apps and windows

Click an app to launch it or bring its windows forward, including windows on another display. The click also asks the app to reopen, so Finder can show a window after you close its last one.

Right-click an app in the dock or a folder to open it or show it in Finder. Running apps also have Hide or Show and Quit actions. Quitting asks the app to close normally, so it can prompt you to save work.

Right-click an app in the dock or a folder for **New Window**. The option appears when the app declares a supported command. Some apps do not expose one. macOS may ask you to let Open Doc control that app the first time you use the command. If permission was denied, review it in **System Settings > Privacy & Security > Automation**.

## Appearance and auto-hide

In Settings, select a dock and open **Appearance**. Choose its screen edge, icon size, material, and auto-hide behavior. Glass has **Clear** and **Regular** styles. Choose a tint colour (Graphite darkens the glass; the others add a soft colour, and Accent follows your system accent colour), then set its strength. A strength of **None** adds no tint. Earlier macOS versions use native blur instead of Liquid Glass.

To reveal a hidden dock, pause the pointer at its screen edge. Move away to hide it. The dock stays open while you use a menu, drag an item, or interact with an open folder or widget. Motion follows the system's Reduce Motion setting.

## Widgets

Open **Widget Library...** to browse and preview widgets. Click an added widget to use its controls or change its settings. Each copy has its own configuration.

See [Widgets](Widgets.md) for available types, custom buttons, and web data.

## Undo and backups

Use **Edit > Undo Dock Edit** to undo changes, including a deleted folder. In Settings, Command-Z and Shift-Command-Z undo and redo dock edits. While typing, they use the text field's history instead. Undo history lasts until you quit the app.

In the Settings toolbar, open **More** and choose **Export Backup...** or **Import Backup...**. Importing adds copies of the saved docks; it does not replace your current setup. File shortcuts may need to be selected again on another Mac.

## Return to Apple's Dock

Choose **Restore Apple's Dock** from the menu bar menu, disable replacement in Settings, or quit Open Doc. Hiding your last visible Open Doc dock also restores Apple's Dock. Showing a dock again resumes replacement if that setting is still enabled.

Open Doc saves your original Dock preferences and restores them on exit. A recovery helper also handles an unexpected exit. After a power loss, launch Open Doc again to recover the previous session. Open Doc does not add itself as a login item automatically.

## Where your data lives

Your workspace is saved in `~/Library/Application Support/OpenDoc/workspace.json`. Use Settings, backups, or the [CLI](../Examples/Agent-CLI.md) to change it. Editing the file while the app is running can overwrite changes.

Widget configuration is stored as plain JSON. Do not include credentials in endpoint URLs. Web widgets keep their last successful fetched value in memory; those cached values are not backups of the source data.
