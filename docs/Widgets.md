# Widgets

Open **Widget Library...** from the dock's settings menu to browse and preview widgets. Add as many copies as you need. Each copy has its own settings. Click a widget in the dock to use or edit it.

## Built-in widgets

| Widget | What it does |
| --- | --- |
| Clock and World clock | Show local time or a chosen time zone. |
| Calendar | Shows the date. It does not read calendar events. |
| Focus timer, Stopwatch, and Countdown | Track time. Timers continue when their editor closes, but do not send notifications or play sounds. |
| Sticky note and Checklist | Keep local text and tasks. Notes save as you type. |
| Hydration | Counts glasses of water and resets each day. |
| Battery | Shows your Mac's battery information. |
| CPU and Memory | Show CPU usage and an estimate of used memory. Memory is not a memory-pressure reading. |
| Web value | Reads a value from an HTTPS JSON endpoint. |
| Custom widget | Combines saved counters, JavaScript formatting, progress, and buttons. Reads webpage HTML or JSON from a local command. |

## Read a JSON value

Choose **Web value**, enter an HTTPS URL, and specify the field to display. For example, `data.total` reads a nested field and `results.0.value` reads a field from the first array entry. Leave the path empty if the response itself is a single value.

You can add a suffix and refresh every 1 to 60 minutes. A failed refresh keeps the last successful value and shows the error in the editor. The widget does not use browser cookies or support custom authentication headers.

## Make an interactive widget

Add a **Custom widget**, open **Configure**, and choose Counter, Water cups, or Webpage value. Use **Preview** to check your draft, then **Save Widget** to apply it.

The display function receives saved `state` and any extracted webpage values. It returns `value`, optional `detail`, and optional `progress` between 0 and 1:

```js
const count = state.count || 0;
const goal = state.goal || 8;
return {
  value: `${count} / ${goal}`,
  detail: 'Glasses today',
  progress: Math.min(1, count / goal)
};
```

To make a widget stand out, return optional presentation fields as well:

- `style`: `'ring'` draws progress as a ring, like an activity ring, with the value beside it. `'bar'` is the default.
- `tint`: a colour (`blue`, `purple`, `pink`, `red`, `orange`, `yellow`, `green`, `teal`, `indigo`, `gray`) or `'level'`, which turns green, then yellow, then red as progress falls. Useful for quotas.
- `symbol`: an SF Symbol name, such as `'drop.fill'`. It replaces the widget's glyph and appears in the ring when no app icon is shown.
- `apps`: up to four bundle identifiers. The icon of the first available app is shown in the ring. For `com.anthropic.claudefordesktop`, Open Doc can also read Claude's logo from an installed CodexBar when Claude Desktop is absent. Open Doc only reads the icon; it never opens either app.

Values Open Doc does not support, such as an unknown style or a colour code, are ignored and the widget renders as usual.

```js
return {
  value: '72% left',
  detail: 'Codex · Weekly · 6d',
  progress: 0.72,
  style: 'ring',
  tint: 'level',
  apps: ['com.openai.codex'],
  symbol: 'chevron.left.forwardslash.chevron.right'
};
```

Add a button with an action that returns the updated state:

```js
state.count = (state.count || 0) + 1;
return state;
```

A widget can have up to four buttons. State survives restarts and backups. Daily reset follows your Mac's local date. In the editor, changing initial state resets the current values when saved. The [CLI](../Examples/Agent-CLI.md) keeps them separate, so set both fields when resetting through a command.

## Read a webpage

Select **Webpage HTML**, enter an HTTPS URL and CSS selector, and optionally choose an attribute to read. For example, `.price` reads text from a price element; an attribute name reads that attribute instead.

The first match is available as `input.text`. Up to 20 matches are available in `input.matches`. Use the display function to clean or format them. The [USD/RUB example](../Examples/USD-RUB.md) includes a URL, selector, and complete display function.

The widget reads the HTML returned by the server. It does not run the site's JavaScript, load other page resources, or use your browser login. If a value only appears after the page runs scripts, try a public JSON endpoint with Web value instead. Selectors may need updating when a site changes.

## Limits

Web responses are limited to 1 MiB and refresh every 1 to 60 minutes. JavaScript display functions and button actions stop after two seconds, can save up to 32 numeric state entries, and have no file, shell, or network APIs. Local commands run separately, as described below. Open Doc does not bundle Node.js.

Custom widgets use the app's value, detail, progress, ring, and button layouts. They cannot add arbitrary UI or embed Apple desktop widgets. Dedicated stock, weather, and media playback integrations are not available.

## Run Bash, Node, or another local command

Add a **Custom widget**, open **Configure**, and choose **Command JSON**, **Codex usage (CodexBar)**, or **Claude usage (CodexBar)**. Review the executable and arguments, check **Allow this widget to run the local command**, then preview and save. Templates start with execution disabled.

Specify an absolute executable path and a JSON array of arguments. Arguments pass directly to the executable without shell expansion. To run a Bash script, use `/bin/bash` with `["/absolute/path/usage.sh"]`. To run JavaScript with Node, select your installed Node executable and use `["/absolute/path/usage.js"]`. Shell pipelines require an explicit shell, for example `/bin/bash` with `["-c", "your pipeline"]`.

Commands run as your Mac account, with access to its files and network. They start in your home directory, receive no stdin, and use a PATH containing `~/.local/bin`, Homebrew, and system directories. Shell startup files are not loaded automatically. Use an absolute Node path for installations managed by nvm. Do not put credentials in widget arguments or scripts, which are saved with workspace backups.

Print one UTF-8 JSON value to stdout. The display function receives that output as `input.text`:

```js
// usage.js, run with an installed Node executable
console.log(JSON.stringify({ value: '72% left', detail: 'Example quota', progress: 0.72 }));
```

```js
// Widget display function
return JSON.parse(input.text);
```

Commands refresh every 1 to 60 minutes, with a configurable timeout of 1 to 25 seconds and a 64 KiB stdout limit. At most two commands run at once. Timeout, excess output, invalid JSON, or a nonzero exit retains the last successful reading and reports an error. Child processes in the command's process group are stopped when the command finishes or exceeds its limits. Commands should complete their work before exiting, not start background services. Diagnostic stderr is discarded; run a failing command in Terminal for details.

The CodexBar presets use its installed helper at `/Applications/CodexBar.app/Contents/Helpers/CodexBarCLI`. Adjust that path if you installed it elsewhere. They request OAuth usage for the selected provider, show the primary quota window when available, and fall back to the secondary window. They display the percentage remaining and time until reset. Sign in to the provider first. If OAuth reports stale credentials while Claude Code works, change `--source` from `oauth` to `cli` in the arguments to use CodexBar’s Claude CLI integration. Open Doc does not store your provider credentials. See [CodexBar's CLI documentation](https://github.com/steipete/CodexBar/blob/main/docs/cli.md).
