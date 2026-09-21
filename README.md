# Open Doc

Open Doc is an open-source dock for macOS. Keep apps in folders, add useful widgets, and arrange more than one dock on your screen. You can edit everything in the app, or use the `opendoc` command to let an AI agent configure widgets and dock appearance.

Requires macOS 14 or later. Release builds support Apple silicon and Intel Macs. The interface uses native Mac controls, with Liquid Glass on macOS 26 and a blur effect on earlier versions.

## Get started

1. Download a published build from [GitHub Releases](https://github.com/Ffinnis/opendoc/releases). If no download is available yet, follow [Build from source](CONTRIBUTING.md#build-from-source).
2. Unzip it, move the app to `/Applications` or `~/Applications`, and launch it.
3. Use the settings button at the end of the dock to add items or change its appearance.

On first launch, Open Doc imports your pinned apps and shows running apps. It also hides Apple's Dock by default. Quit Open Doc or choose **Restore Apple's Dock** from its menu bar menu to bring it back. Your Apple Dock shortcuts stay unchanged.

## What you can do

- Drag apps to reorder them or group them into folders. Folder dots show how many contained apps are running.
- Add clocks, timers, notes, checklists, system stats, and interactive custom widgets.
- Create extra docks with their own items, position, size, glass tint, and auto-hide settings.
- Open folders with one click. Larger folders have pages with up to nine apps each.
- Right-click an app for actions such as **New Window**, when that app supports it.
- Let an agent add widgets, format web data, or change dock appearance through the CLI.

Read [Using Open Doc](docs/Using-Open-Doc.md) for drag and drop, folders, backups, and settings. The [widget guide](docs/Widgets.md) explains the built-in widgets and custom scripts.

## Use it with an agent

Launching Open Doc from Applications installs the `opendoc` command. Open a new terminal, keep the app running, and start here:

```sh
opendoc help
opendoc state
opendoc help widget.add
opendoc schema
```

An agent can discover the available commands, preview a widget, validate an edit, and apply it without controlling your mouse. The CLI currently supports widgets and dock settings. Use the app to create docks and organize application folders.

See the [CLI guide](Examples/Agent-CLI.md) for a complete interactive widget example, or try the [USD/RUB widget](Examples/USD-RUB.md).

## Updates and data

Installed copies check for updates daily through Sparkle. You can also choose **Check for Updates...** or turn automatic checks off in the app menu. Downloads come from GitHub Releases. Only published, verified releases reach the update feed.

Your dock configuration is stored locally. There are no analytics. Network access is used for updates, web widgets you configure, and links you open. Widget settings are plain JSON, so avoid putting secrets in URLs. Use **Export Backup...** in Settings to save a copy of your setup.

## Current limits

Open Doc is still in development. It does not reserve desktop space, arrange other apps' windows, or provide window previews. It cannot embed Apple's desktop widgets. Webpage widgets read the returned HTML, so they cannot use your browser login or values loaded by a site's JavaScript.

## Contribute

[CONTRIBUTING.md](CONTRIBUTING.md) covers setup, isolated testing, and pull requests. Coding agents should also read [AGENTS.md](AGENTS.md). Maintainers can find the publishing steps in the [release guide](docs/Releasing.md).

Open Doc is licensed under [MIT](LICENSE). It was inspired by [Dockset's public screenshots](https://dockset.app/). No Dockset code or assets are included. App icons come from the apps installed on your Mac and belong to their respective owners.
