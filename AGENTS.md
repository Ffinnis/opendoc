# Working on Open Doc

Keep this file limited to project-specific mistakes worth preventing. If a rule compensates for confusing code, fix the code first. Build commands and contribution expectations live in [CONTRIBUTING.md](CONTRIBUTING.md).

- Open Doc targets macOS only. The desktop dock is native AppKit; do not replace it with SwiftUI or a web UI.
- Normal Mac launch can hide Apple's Dock, import pinned apps, and install the CLI when run from Applications. Use `--ui-testing <fresh UUID>` for an isolated settings session. Do not use the installed app or its workspace as a test fixture.
- `~/Library/Application Support/OpenDoc` contains real user state. For authorized live edits, use `opendoc help`, `opendoc schema`, and `opendoc state`; apply changes through the CLI, not direct JSON writes. After a timed-out mutation, read state before retrying. See [the CLI guide](Examples/Agent-CLI.md).
- Persist edits through `DockStore`. Preserve validation, atomic writes, undo, and ownership by profile ID. The selected Settings profile may differ from the dock being edited.
- Dock replacement must remain reversible on quit, disable, last-dock hide, and crash recovery. Preserve the original system preferences. Do not test this by killing processes by name or replacing the contributor's installed app.
- Mouse movement must not fetch data, evaluate scripts, rebuild the dock, or redraw widget text. Align hit testing with presented animation geometry and keep widgets inside the shelf. Check edge items, rapid direction changes, clicks, and Reduce Motion after motion changes.
- Custom scripts run in a bounded worker without native bridges. HTML extraction is inert. Preserve those boundaries and request limits when changing widgets.
- CLI help, schema, validation, and execution must agree. Test affected commands with an isolated store and include rejected edits that leave state unchanged.
- Report build, test execution, and visual/performance checks separately. A compiled test target is not a passing test run; a screenshot is not evidence of 120 fps.

Add guidance only after a concrete failure exposes a lasting constraint. Keep file inventories, session history, local machine paths, and generic coding advice out of this file.
