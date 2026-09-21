# Widgets

Clock, Calendar, Focus timer, Sticky note, Checklist, Hydration, Stopwatch, Countdown, Battery, World clock, CPU, Memory, Web value, and Custom widget are implemented on Mac. Add multiple instances and configure them independently. CPU, Memory, Web value, programmable custom widgets, and application folders are Mac features.

Notes save automatically while you type and flush pending edits when closed. Notes and checklists are local. Calendar shows dates without reading system events. Hydration resets daily. Timers use saved timestamps and continue when their editor closes, but do not schedule sounds or notifications. Battery reads the Mac's actual power-source information. CPU samples system usage; Memory estimates active, wired, and compressed memory, rather than memory pressure. World clock supports the system's time-zone catalog.

**Web value** reads a scalar field from an HTTPS JSON endpoint. Enter a dotted field path such as `data.total` or `results.0.value`, an optional suffix, and a refresh interval from 1 to 60 minutes. An empty path reads a root scalar. Requests have a timeout and a 1 MiB response limit, use no cookie or credential storage, and show errors in the editor. A failed refresh keeps the last successful value for the current configuration. Values are cached in memory; configuration is included in backups. Endpoints requiring custom authentication headers are not supported.

**Custom widget** supports saved numeric state, JavaScript formatting, a progress bar, and up to four programmable buttons. Open **Configure** and choose Counter, Water cups, or Webpage value. Preview evaluates the current draft without saving it. Save Widget applies it and opens the interactive view. Existing manual widgets keep their text until configured.

See the [USD/RUB example](../Examples/USD-RUB.md) for a complete webpage widget with CSS extraction, rate formatting, and the source's effective date.

The display function receives `state`, `input.text`, and `input.matches`. Return an object with `value`, optional `detail`, and optional `progress` from 0 to 1. For example:

```js
const count = state.count || 0;
const goal = state.goal || 8;
return { value: `${count} / ${goal}`, detail: 'Glasses today', progress: count / goal };
```

A button action receives the same inputs and returns the updated state:

```js
state.count = (state.count || 0) + 1;
return state;
```

State survives restarts and exports. Optional daily reset uses the Mac's local date. Changing initial state resets current values when saved. Actions commit only after both action and display functions succeed. Each script runs in a separate short-lived JavaScriptCore process with a two-second deadline and no exposed file, shell, or network APIs. There is no Node.js runtime. State is limited to 32 numeric entries. Scripts cannot supply arbitrary native layouts.

For **Webpage HTML**, enter an HTTPS URL, a CSS selector such as `.price` or `div[data-total]`, and optionally an attribute name. The first match becomes `input.text`; up to 20 matches are available in `input.matches`. Use JavaScript to clean or format those values. Requests are cached, limited to 1 MiB, and refresh every 1 to 60 minutes. Parsing does not execute page scripts or load subresources. Browser login and values populated by a site's JavaScript are not supported; a site's public JSON endpoint can be used with Web value instead.

Arbitrary Apple desktop widgets and WidgetKit extensions cannot be embedded. Dedicated stock, weather, and media playback integrations are not implemented. Public service data can be displayed through compatible HTML or JSON endpoints. Sample market or revenue values are not presented as live data.

