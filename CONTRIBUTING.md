# Contributing to Open Doc

Bug fixes, UI improvements, accessibility work, and clearer documentation are welcome. For a large feature, open an issue first so we can agree on the behavior before you spend time building it.

## Build from source

You need a Mac with Xcode 26 or later. The app runs on macOS 14 or later. Xcode downloads the pinned Sparkle dependency automatically.

Open `opendoc.xcodeproj`, choose the `opendoc` scheme, and select **My Mac**. For a command-line build without a signing account:

```sh
xcodebuild -project opendoc.xcodeproj -scheme opendoc \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath build/mac CODE_SIGNING_ALLOWED=NO build
```

To use it as your everyday dock, launch the built app:

```sh
open build/mac/Build/Products/Release/opendoc.app
```

A normal launch uses your real workspace and can hide Apple's Dock. For development, use the isolated session below. See [Signing](docs/Signing.md) if you need a signed build.

## Test without changing your dock

Start a separate settings session with temporary data:

```sh
build/mac/Build/Products/Release/opendoc.app/Contents/MacOS/opendoc \
  --ui-testing "$(uuidgen)"
```

This session does not replace Apple's Dock, import your pinned apps, install the CLI, or start the agent connection. Test actual Dock replacement and the installed CLI in a separate macOS account or disposable machine.

Tests that save data must use a fresh `DockStore(fileURL:)`. Do not use the installed app or `~/Library/Application Support/OpenDoc` as test data. Stop only processes you started for testing.

## Check your change

Run the Mac build for code or configuration changes. Run unit tests with:

```sh
xcodebuild -project opendoc.xcodeproj -scheme opendoc \
  -destination 'platform=macOS' -derivedDataPath build/tests \
  DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual \
  -parallel-testing-enabled NO -only-testing:opendocTests test
```

Add a focused regression test for a bug fix. For dock interactions, also check edge items, side docks, rapid pointer movement, dragging, popovers, auto-hide, and Reduce Motion. For CLI changes, check command help, rejected edits, dry runs, and revision conflicts.

UI tests need a logged-in desktop and the required macOS Automation permission. Use the same command with `-only-testing:opendocUITests/NativeDockUITests` instead of the unit-test target.

GitHub CI runs unit tests with Reduce Motion on and off, checks offline CLI help, and tests update signature validation. It does not run UI tests. Report what actually ran. A successful build is not a passing test run, and a screenshot does not establish animation frame rate.

## Send a pull request

Explain the problem, the resulting behavior, and how you checked it. Include before/after images for visible changes and mention any checks you could not run. Keep unrelated edits in separate PRs.

Keep the interface native to macOS. Changes must preserve saved workspaces, undo, and the ability to restore Apple's Dock. Read [AGENTS.md](AGENTS.md) for the project rules that also apply to coding agents.

Do not include personal workspace exports, credentials, signing keys, build output, or screenshots with private information. Do not bundle other apps' icons or Dockset assets. Contributions use the [MIT license](LICENSE); keep existing copyright and third-party license notices.
