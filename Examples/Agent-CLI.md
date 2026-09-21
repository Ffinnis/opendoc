# Agent CLI

Move Open Doc to `/Applications` or `~/Applications` and launch it once. The app installs `opendoc` in `~/.local/bin`. If needed, it adds that directory to your zsh or bash login profile; open a new terminal to load the change. No repository checkout or package manager is required.

```sh
opendoc --help
opendoc help widget.add
opendoc widget.update --help
opendoc help --json
opendoc schema
opendoc state
```

The app menu also includes **Install Command Line Tool…** for repair or development builds. Installation preserves unrelated commands with the same name. Launching the app after moving it updates the launcher. The running app handles commands over a local socket; launching the CLI does not open a second GUI instance.

Help is bundled in the executable and works even when the app is closed. Each command explains required input fields, accepted values, an example, the result, and patch rules. `opendoc help COMMAND --json` returns the same documentation as structured JSON. The live `schema` response also includes `commandHelp`.

For development only, `Scripts/opendoc` can target a build through `OPENDOC_APP`. The installed command does not depend on that script or this repository.

Responses contain `ok`, `result`, and `revision`. Failures contain `ok: false` and an `error`, with exit status 1. UUIDs and the revision come from `state`. No UI automation or manual workspace-file editing is involved.

## Add an interactive widget

Save this as `/tmp/water-widget.json`, replacing `DOCK_UUID` with the target dock's ID:

```json
{
  "dockID": "DOCK_UUID",
  "kind": "custom",
  "patch": {
    "title": "Water cups",
    "custom": {
      "initialState": {"count": 0, "goal": 8},
      "state": {"count": 0, "goal": 8},
      "resetDaily": true,
      "renderScript": "return { value: `${state.count} / ${state.goal}`, detail: 'Glasses today', progress: state.count / state.goal };",
      "actions": [
        {"title": "Add a Glass", "script": "state.count += 1; return state;"},
        {"title": "Reset", "script": "state.count = 0; return state;"}
      ]
    }
  }
}
```

```sh
opendoc widget.add --input /tmp/water-widget.json --dry-run
opendoc widget.add --input /tmp/water-widget.json --if-revision REVISION
```

The app generates missing action IDs. The response includes the created widget's ID. Widget kinds and optional configuration defaults are returned by `schema`.

## Edit a widget or the dock

```sh
opendoc widget.update --input - <<'JSON'
{"itemID":"ITEM_UUID","patch":{"title":"Daily water","custom":{"renderScript":"return { value: state.count + ' glasses', detail: 'Today', progress: state.count / 8 };"}}}
JSON

opendoc dock.update --input - --dry-run <<'JSON'
{"dockID":"DOCK_UUID","patch":{"appearance":{"size":48,"material":"Glass","position":"Bottom","autoHide":true,"showLabels":false}}}
JSON
```

Remove `--dry-run` to apply an appearance edit. `dock.update` also accepts a `visible` boolean. Hiding the last visible dock restores Apple's Dock through the app's existing behavior.

Objects merge; arrays and the numeric `state`/`initialState` dictionaries replace. Omitted fields stay unchanged. Set optional fields to `null` to clear them. Changing initial state through the CLI does not implicitly overwrite saved state; set both explicitly when resetting a counter. IDs and widget kinds are immutable. Unknown fields are rejected. Dates use seconds since 2001-01-01 UTC, matching the workspace format.

## Preview custom code

```sh
opendoc widget.preview --input - <<'JSON'
{"custom":{"state":{"count":3},"renderScript":"return { value: state.count + ' glasses', progress: state.count / 8 };"}}
JSON
```

For a webpage preview, include `source: "webpage"`, `endpoint`, `selector`, and `renderScript` in `custom`. Preview may fetch the configured HTTPS URL and executes the script in the same isolated worker as the widget. It does not save configuration. The [USD/RUB example](USD-RUB.md) supplies a working source, selector, and display function.

## Connection and concurrency

The running app serves a same-user Unix socket under `/tmp/opendoc-agent-UID/`. The directory has mode 0700, the socket 0600, and both client and server verify the peer's user ID. It opens no TCP port and exposes no shell execution operation. Requests run serially through the app's main-actor model; socket I/O stays off the UI thread. Closing the app stops the service. Test-mode app instances do not start it.

`ifRevision` hashes the current archive and visible dock IDs. A mismatch returns a conflict before applying a change. Read state and reapply your intended patch. A timed-out mutation can have succeeded, so inspect state before retrying. This is a local CLI protocol, not an MCP server. An MCP adapter can call these operations without changing the app's command handling.

### Glass appearance

Use `dock.update` with `patch.appearance.glassStyle` set to `Clear` or `Regular`.
`glassTint` adds a dark tint from `0` to `1`; `0` leaves Apple's material untinted.
These settings apply to the shelf at rest and during magnification. They are also
available under Appearance in Settings. macOS versions before 26 use a native blur fallback.
