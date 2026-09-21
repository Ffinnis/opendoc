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
| Custom widget | Combines saved counters, JavaScript formatting, progress, and buttons. It can also read webpage HTML. |

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

Web responses are limited to 1 MiB and refresh every 1 to 60 minutes. Custom scripts stop after two seconds, can save up to 32 numeric state entries, and have no file, shell, or network APIs. There is no Node.js runtime. Use the widget's source settings to fetch data.

Custom widgets use the app's existing value, detail, progress, and button layout. They cannot add arbitrary UI or embed Apple desktop widgets. Dedicated stock, weather, and media playback integrations are not available.
