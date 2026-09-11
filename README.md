# Pomodoro for Omarchy

A pomodoro timer that lives in the [Omarchy](https://omarchy.org/) status bar.
It counts down a work session, announces the end with a notification and a
chime, then rolls straight into a break and back again. Durations are set from
the bar, the scroll wheel, or a terminal command, and they persist across
restarts.

```
idle      󱫠  25/5   −  ▭▭▭▭  +  ↺     cycle shown when idle at full duration
work      󱫠  23:41  −  ▰▰▱▱  +  ↺     timer glyph, phase-tinted while running
break     󰅶  04:12  −  ▰▰▰▱  +  ↺     coffee glyph
```

## Install

```bash
omarchy plugin add https://github.com/joaobordignon/omarchy-pomodoro.git --enable
```

Plugins land disabled unless you pass `--enable`, so you can read the code
first. To place it in a specific spot on the bar:

```bash
omarchy bar put joaobordignon.pomodoro --section center --after omarchy.clock
```

Optionally put the `pomodoro` command on your `PATH`:

```bash
ln -s ~/.config/omarchy/plugins/joaobordignon.pomodoro/bin/pomodoro ~/.local/bin/pomodoro
```

## The bar widget

The glyph always tells you the phase — timer for work, coffee for break —
independent of whether the clock is running. Run state is carried by the
border and by the digits moving.

The time slot shows the cycle (`25/5`) whenever the timer is idle at its full
duration, and the countdown (`23:41`) once it is running or paused part-way
through. An idle timer reading `25:00` would only be restating the work
duration, so those pixels carry the cycle instead.

| Control | Left click | Right click | Scroll |
|---------|-----------|-------------|--------|
| Glyph | Start / pause | Switch phase | ±1 min |
| Time | Start / pause | Switch phase | ±1 min |
| `−` / `+` | ∓1 / ±1 min | — | ±1 min |
| Progress bar | Start / pause | — | ±1 min |
| `↺` | Reset phase | — | ±1 min |

Adjusting always changes the phase you are currently in: work minutes while
working, break minutes while on a break. Adjusting a *running* timer shifts the
remaining time by the same amount rather than restarting it.

On a vertical bar the widget collapses to the glyph plus whole minutes
remaining; the `−`, `+`, progress bar and reset controls are hidden, and the
cycle is available from the tooltip.

## The `pomodoro` command

```
pomodoro                 Current phase, time left, and cycle (default)
pomodoro list            Available cycle presets
pomodoro use <preset>    Apply a preset by name
pomodoro set <w> <b>     Apply a custom cycle, in minutes (1-180)
pomodoro auto <on|off>   Auto-advance between work and break
pomodoro start | pause | toggle | reset | mode
```

```console
$ pomodoro
Work   25:00  (paused)
Cycle  Classic 25/5
Auto   on

$ pomodoro list
 * classic     25/5    Classic
   short       15/3    Short bursts
   long        50/10   Long focus
   deep        45/15   Deep work
   desktime    52/17   DeskTime
   ultradian   90/20   Ultradian

$ pomodoro use long
Cycle set to Long focus 50/10

$ pomodoro set 35 7
Cycle set to 35/7
```

Presets are a table at the top of `bin/pomodoro`; edit it to add your own.

Applying a named preset stores its name, so the tooltip reads
`cycle DeskTime 52/17`. Hand-tuning either duration with `+`/`−` drops the
name, because the cycle is no longer the preset it was named after.

Changing the cycle while a session is running leaves that session alone — the
new durations take effect from the next phase.

## Configuration

Settings live in the widget's entry in `~/.config/omarchy/shell.json`:

| Key | Type | Default | Meaning |
|-----|------|---------|---------|
| `workMinutes` | number | `25` | Work session length, 1-180 |
| `breakMinutes` | number | `5` | Break length, 1-180 |
| `autoCycle` | boolean | `true` | Switch phase and start it automatically when a session ends |
| `cycleName` | string | — | Label shown beside the cycle in tooltips |

```json
{ "id": "joaobordignon.pomodoro", "workMinutes": 50, "breakMinutes": 10, "cycleName": "Long focus" }
```

**Prefer the `pomodoro` command or `omarchy bar set` over editing that file by
hand.** The shell rewrites the whole of `shell.json` from its in-memory copy
whenever a widget saves a setting, so an edit made while the shell is running
is lost the next time you press `+`. If you do edit it directly, run
`omarchy restart shell` afterwards.

## Keybindings

The widget answers on the IPC target `joaobordignon.pomodoro`, so any action can be
bound in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER ALT", "P", "Pomodoro: start/pause", "omarchy-shell joaobordignon.pomodoro toggle")
o.bind("SUPER ALT", "R", "Pomodoro: reset",       "omarchy-shell joaobordignon.pomodoro reset")
o.bind("SUPER ALT", "M", "Pomodoro: switch phase","omarchy-shell joaobordignon.pomodoro mode")
```

## IPC reference

```bash
omarchy-shell joaobordignon.pomodoro <method> [args...]
```

| Method | Arguments | Returns |
|--------|-----------|---------|
| `status` | — | JSON: phase, running, remainingSeconds, totalSeconds, workMinutes, breakMinutes, cycleName, autoCycle |
| `toggle` / `start` / `pause` | — | — |
| `reset` | — | — |
| `mode` | — | — |
| `add` / `sub` | — | — |
| `cycle` | `<work> <break> [name]` | applied cycle, e.g. `50/10` |
| `auto` | `<true\|false>` | `on` or `off` |

`status` is JSON so it can drive other status tools:

```bash
omarchy-shell joaobordignon.pomodoro status | jq -r '.phase'
```

## How it behaves

**Multi-monitor.** The bar is built once per monitor, so several copies of the
widget are live at the same time. They each run their own countdown and are
kept in step by relaying state changes to their peers. Only one copy is allowed
to send the completion notification, so a multi-monitor desk gets one
notification rather than one per screen.

**Completion.** The notification announces the phase that just *ended*
("Pomodoro Completed!" / "Break Finished!"), then the next phase starts if
`autoCycle` is on. With `autoCycle` off the timer stops at `00:00` and holds
its phase.

## Requirements

- Omarchy with the Quickshell-based shell (`omarchy-shell`)
- A Nerd Font as the bar font, for the timer, coffee and reset glyphs
- `python3`, for the `pomodoro` command's status output
- `libcanberra` for the completion chime — optional; without it the
  notification still fires

## Development

Saving a file under `~/.config/omarchy/plugins/` hot-reloads the plugin's code.
**The IPC target does not follow that reload** — it stays bound to the
pre-reload instance, so a newly added IPC method reports `Function not found`
and existing ones silently run the old code. Run `omarchy restart shell` before
testing anything over IPC or a keybinding.

```bash
omarchy plugin validate ~/.config/omarchy/plugins/joaobordignon.pomodoro
omarchy restart shell
journalctl --user -f | grep -i pomodoro
```

## License

MIT — see [LICENSE](LICENSE).
