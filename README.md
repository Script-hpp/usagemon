# usagemon

A KDE Plasma 6 panel widget that shows your [Claude Code](https://claude.com/claude-code)
subscription usage — session and weekly rate limits — at a glance, so you don't
have to type `/usage` in a terminal every time.

It periodically runs `claude -p "/usage"` in the background, parses the output,
and shows a compact, color-coded readout in your panel. Click it for a popup
with the full breakdown and reset times.

## Features

- **Panel readout**: `⏱ 29% · 📅 36%` — session and week usage side by side,
  each with its own icon (stopwatch / week calendar).
- **Threshold colors**: the percentages and icons turn from green → yellow → red
  as usage crosses configurable warning and critical thresholds.
- **Detail popup**: per-limit progress bars (session, week, plus any extra limits
  such as a per-model weekly limit) with reset times.
- **Active model**: reads your configured model from `~/.claude/settings.json`
  and shows it in the popup header and tooltip.
- **Auto refresh** on a configurable interval, plus manual refresh
  (middle-click the panel item, the popup's refresh button, or the context menu).

## Requirements

- KDE Plasma 6
- The `claude` CLI installed and authenticated. The widget only shells out to
  this CLI — it does **not** talk to any Anthropic API directly.

## Install

```sh
git clone https://github.com/Script-hpp/usagemon.git
cd usagemon
./install.sh
```

Then right-click your panel → **Add Widgets…** → search for **usagemon** and
add it.

## Uninstall

```sh
./uninstall.sh
```

## Configuration

Right-click the widget → **Configure usagemon…** → **General**:

| Option | Default | Description |
| --- | --- | --- |
| Claude command | `claude` | Path/name of the `claude` binary |
| Poll interval (seconds) | `30` | How often to refresh (min 10) |
| Warn threshold (%) | `75` | Usage at which the readout turns yellow |
| Critical threshold (%) | `90` | Usage at which the readout turns red |
| Wider layout | off | Widen the popup and show the full reset time (incl. timezone) |

## How it works

There is no public Anthropic API for Claude Code's subscription rate limits
(session %, week %) — that data is only exposed through the CLI's `/usage`
command. usagemon runs `claude -p "/usage"` on a timer (inside a login shell, so
it picks up a `claude` installed in `~/.local/bin` and similar), and parses the
plain-text response in [`package/contents/ui/UsageParser.js`](package/contents/ui/UsageParser.js).
If Anthropic changes that output format, parsing may need updating there.

## License

MIT — see [LICENSE](LICENSE).
