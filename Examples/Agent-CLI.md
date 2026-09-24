# Control Open Doc from the command line

The `opendoc` command lets you inspect docks, add or edit widgets, and change dock appearance. It works with scripts and AI agents. No mouse control or repository checkout is needed.

The CLI does not yet create docks or move apps into folders. Use the app for those actions. It is a local CLI, not an MCP server.

## Set up

Move Open Doc to `/Applications` or `~/Applications` and launch it. The app installs the command in `~/.local/bin` and, if needed, adds that directory to your zsh or bash login profile. Open a new terminal afterward.

If the command is missing, choose **Install Command Line Tool...** in the app menu. Installation preserves any unrelated command already named `opendoc`. Launching the app again after moving it repairs its launcher.

```sh
opendoc help
opendoc help widget.add
opendoc help --json
```

Help works while the app is closed. All other commands need Open Doc running. Calling the CLI does not launch a second copy of the app.

## Start with the current state

```sh
opendoc state
opendoc schema
```

`state` returns the docks in `result.archive.profiles` and a top-level `revision`. Choose the intended dock by name, then use its `id` in commands. Widget IDs come from that dock's `items`. Commands require UUIDs, not names.

`schema` lists widget kinds, defaults, templates, and accepted appearance values. For exact command fields and examples, use `opendoc help COMMAND`. Add `--json` to help for structured output.

| Command | Purpose |
| --- | --- |
| `state` | Read docks, items, visible docks, and the current revision. |
| `schema` | Discover supported configuration. |
| `widget.add` | Add a widget to an existing dock. |
| `widget.update` | Change selected widget fields. |
| `widget.remove` | Remove a widget. |
| `widget.preview` | Evaluate custom code without saving a widget. |
| `dock.update` | Change a dock's name, appearance, or visibility. |

## Add a water counter

Save this as `/tmp/water-widget.json`. Replace `DOCK_UUID` with the dock's `id` from `state`.

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
        {"title": "Add a glass", "script": "state.count += 1; return state;"},
        {"title": "Reset", "script": "state.count = 0; return state;"}
      ]
    }
  }
}
```

Validate first, then apply. Replace `REVISION` with the revision from your latest `state` response.

```sh
opendoc widget.add --input /tmp/water-widget.json --dry-run
opendoc widget.add --input /tmp/water-widget.json --if-revision REVISION
opendoc state
```

The add response contains the new widget in `result`. Keep `result.id` for later edits. Button IDs are generated automatically.

## Edit appearance

This example validates settings for a bottom dock with clear glass and a soft blue tint:

```sh
opendoc dock.update --input - --dry-run <<'JSON'
{
  "dockID": "DOCK_UUID",
  "patch": {
    "appearance": {
      "position": "Bottom",
      "material": "Glass",
      "glassStyle": "Clear",
      "glassTint": 0.3,
      "tintColor": "Blue",
      "size": 48,
      "autoHide": true
    }
  }
}
JSON
```

Replace the dock ID, then replace `--dry-run` with `--if-revision REVISION` to apply it. `dock.update` also accepts `visible`. Hiding the last visible dock restores Apple's Dock.

## Preview a display function

```sh
opendoc widget.preview --input - <<'JSON'
{"custom":{"state":{"count":3},"renderScript":"return { value: state.count + ' glasses', progress: state.count / 8 };"}}
JSON
```

Preview returns the displayed value, detail, and optional progress, style, tint, symbol, and apps. A webpage preview may fetch its URL, even with `--dry-run`. It never saves the widget. See [Widgets](../docs/Widgets.md) for script inputs and [USD/RUB](USD-RUB.md) for a webpage example.

## Add a command widget

`schema.customTemplates` includes `command`, `codex`, and `claude`. Each starts with `command.enabled: false`. Enable execution only after reviewing the executable and arguments. For example, use this as the input to `widget.add`, replacing the dock UUID:

```json
{
  "dockID": "DOCK_UUID",
  "kind": "custom",
  "patch": {
    "title": "Local metric",
    "custom": {
      "source": "command",
      "command": {
        "enabled": true,
        "executable": "/bin/bash",
        "arguments": ["/absolute/path/metric.sh"],
        "timeout": 20
      },
      "refreshInterval": 300,
      "renderScript": "return JSON.parse(input.text);",
      "actions": []
    }
  }
}
```

The script must print JSON such as `{"value":"72% left","detail":"Quota","progress":0.72}`. Add `"style":"ring","tint":"level"` to show the quota as a ring that turns yellow and then red as it runs low; see [Widgets](../docs/Widgets.md) for `symbol` and `apps`. Arguments are literal, without shell expansion. Use your installed Node executable to run a `.js` file. Commands have a 64 KiB output limit and a 1–25 second timeout.

`widget.add` and `widget.update` with `--dry-run` validate without executing or saving. **`widget.preview` executes an enabled command, even with `--dry-run`.** Saving an enabled widget allows background refresh to execute it. Commands run with the user's file and network access, separately from the restricted display function. See [Widgets](../docs/Widgets.md#run-bash-node-or-another-local-command) for runtime details.

## Rules for edits

- Pass the fields directly as JSON with `--input FILE` or `--input -`. Do not wrap them in `op` or `params`.
- Objects merge. Arrays and the `state` and `initialState` dictionaries replace their previous values.
- Omitted fields stay unchanged. `null` clears optional fields. IDs and widget kinds cannot change. Unknown fields are rejected.
- To reset a counter through the CLI, set both `initialState` and `state`. Changing only the initial state leaves the current value alone.
- Date fields use seconds since January 1, 2001 UTC.

Successful responses contain `ok: true`, `result`, and `revision`. Errors contain `ok: false` and `error`, and exit with status 1.

For each edit, read state, inspect command help, validate with `--dry-run`, apply with `--if-revision`, and read state again. If the revision changed, inspect the new state before trying again. If a command timed out, it may already have applied. Check before repeating it.

Commands connect locally as your macOS user. Closing Open Doc stops the connection. Edit through this CLI rather than writing to the workspace file.
