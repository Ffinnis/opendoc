# Contributing to Open Doc

Bug fixes, native UI improvements, accessibility work, tests, and documentation are welcome. For a large feature or architectural change, open an issue describing the problem and intended behavior before starting implementation.

## Build from source

Use a Mac with Xcode 26 or later and its command-line tools selected in Xcode Settings. The deployment target is macOS 14. Xcode resolves the pinned Sparkle package automatically.

Open `opendoc.xcodeproj` and select the shared `opendoc` scheme. Choose My Mac. The project does not select a signing team for contributors. For signed development or distribution, create `Configuration/LocalSigning.xcconfig` with `DEVELOPMENT_TEAM = YOUR_TEAM_ID`. This ignored file selects your team in Xcode for all targets without committing account details. Xcode can manage development signing automatically. Keep certificates and provisioning profiles out of the repository.

See [Signing and notarization](docs/Signing.md) for Developer ID releases.

Unsigned Mac build:

```sh
xcodebuild -project opendoc.xcodeproj -scheme opendoc \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath build/mac CODE_SIGNING_ALLOWED=NO build
```

## Use isolated development data

A normal Mac launch replaces Apple's Dock by default. It reads and writes the same workspace as an installed copy, and a build launched from Applications may update `~/.local/bin/opendoc`. Do not install a development build over your everyday copy just to test a change.

For a settings-only session with a fresh temporary archive and system Dock replacement disabled:

```sh
build/mac/Build/Products/Release/opendoc.app/Contents/MacOS/opendoc \
  --ui-testing "$(uuidgen)"
```

The test session skips pinned-app import, CLI installation, and the agent socket. To exercise actual replacement or the installed CLI, use a separate macOS account or disposable machine. Stop only a test process you started. Never kill apps by a broad name/path pattern.

Tests that touch persistence should construct `DockStore(fileURL:)` with a fresh temporary URL. Never write directly to a running user's archive. The installed `opendoc` command is for deliberate live changes, as described in [the CLI guide](Examples/Agent-CLI.md).

## Validate a change

Run the Mac build for code or configuration changes.

Run unit tests:

```sh
xcodebuild -project opendoc.xcodeproj -scheme opendoc \
  -destination 'platform=macOS' -derivedDataPath build/tests \
  DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual \
  -parallel-testing-enabled NO -only-testing:opendocTests test
```

UI tests require a logged-in desktop, a working XCTest runner, and macOS Automation permission:

```sh
xcodebuild -project opendoc.xcodeproj -scheme opendoc \
  -destination 'platform=macOS' -derivedDataPath build/tests \
  DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual \
  -parallel-testing-enabled NO -only-testing:opendocUITests/NativeDockUITests test
```

If the runner cannot launch, capture the error and report the run as blocked. `build-for-testing` checks compilation only. Do not describe it as a test pass. The GitHub workflow runs Mac unit tests with ad hoc signing and checks CLI help; it does not run UI tests.

Add focused regression tests for changed behavior. Test rejected edits without state changes, persistence round trips, and undo when relevant. Avoid tests that merely repeat implementation details.

For dock interaction changes, check bottom and side docks, the first and last item, mixed widgets/apps, narrow displays, rapid hover changes, click and right-click, folder/widget popovers, auto-hide, and Reduce Motion. Keep animation targets clickable during transitions. Measure frame pacing in a Release build before making performance claims.

For CLI changes, check offline help, schema, required/unknown fields, dry-run, revision conflicts, and result/error JSON. For web widgets, prefer deterministic fixtures; live endpoints are supplemental checks.

## Submit a pull request

Keep each PR focused on one problem. Explain what triggers the problem, what changes for the user, and which checks actually ran. Include before/after images for UI changes and note checks you could not run. Review generated or agent-written changes yourself.

Preserve native AppKit, supported archive decoding, and reversible system Dock behavior. Prefer Apple's frameworks and existing code to new dependencies or generic layers. Update user docs when behavior changes, and CLI help when commands change. Keep developer setup details in this guide.

Do not include personal workspace exports, endpoint credentials, signing identities, app bundles, build results, or screenshots containing private information. Application icons displayed at runtime belong to their respective owners; do not bundle other apps' artwork or Dockset assets.

Contributions are provided under the repository's [MIT license](LICENSE). Keep existing copyright notices and identify third-party code and its license in the PR. Be specific and respectful in reviews; critique the code and behavior.
