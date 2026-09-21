# Working on Open Doc

Read [CONTRIBUTING.md](CONTRIBUTING.md) for setup and checks. To configure a user's running dock, use the [CLI guide](Examples/Agent-CLI.md).

- Open Doc targets macOS only. Use AppKit for the desktop interface. Do not replace it with SwiftUI or a web UI.
- A normal launch can hide Apple's Dock, import pinned apps, and install the CLI from Applications. Use `--ui-testing <fresh UUID>` for an isolated settings session. The installed app and its workspace are not test fixtures.
- `~/Library/Application Support/OpenDoc` contains real user data. For authorized live edits, use `opendoc help`, `opendoc schema`, and `opendoc state`, then apply changes through the CLI. Do not write the JSON directly. After a timeout, read state before retrying an edit.
- Save edits through `DockStore`. Preserve validation, atomic writes, undo, and the target profile ID. The dock being edited may differ from the profile selected in Settings.
- Restore Apple's original Dock preferences on quit, replacement disable, hiding the last dock, and crash recovery. Do not test this by killing apps by name or replacing a contributor's installed app.
- Pointer movement must not fetch data, run scripts, rebuild the dock, or redraw widget text. Click targets must follow the visible icons. Keep widgets inside the shelf and check edge items, rapid direction changes, clicks, and Reduce Motion after animation changes.
- Keep custom scripts in their bounded worker without native bridges. HTML extraction must not run page scripts. Preserve request and execution limits.
- CLI help, schema, validation, and execution must agree. Test commands with an isolated store, including rejected edits that leave state unchanged.
- Report builds, executed tests, and visual or performance checks separately. Compiling a test target is not running it. A screenshot does not prove 120 fps.

Keep this file focused on project-specific mistakes worth preventing. Put build instructions and general contribution guidance in CONTRIBUTING.md. Add a rule only after a concrete failure shows it is needed.
