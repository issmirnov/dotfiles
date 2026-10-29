# Claude peak-hours chip: design

**Date:** 2026-10-29
**Status:** Draft, awaiting review.
**Author:** Ivan + Claude

## Motivation

During weekday peak hours, Claude session limits drain faster. The site
https://claude-peak-time.pages.dev/ shows the window: Monday to Friday,
05:00–11:00 America/Los_Angeles. In Denver that is 06:00–12:00 all year,
because both cities change their clocks on the same dates. The bar has a
usage chip for each Claude account, but nothing shows peak hours.

On 2026-05-06, Anthropic removed the peak-hour cut for Claude Code on the Pro
and Max plans. Source: [Anthropic](https://www.anthropic.com/news/higher-limits-spacex).
The post does not mention Team, Enterprise, or claude.ai. The chip shows the
window in all cases. It does not know the plan of each account.

## Decisions (locked in brainstorming)

- **Place:** a chip at the left end of the top-right cluster, just before the
  Claude pool chips.
- **During peak:** `⚡ peak 49m` in amber text (`#f0c489`, the pastel
  `Theme.usageWarn`) on the normal chip surface. The countdown runs to 11:00
  Pacific.
- **In the hour before peak:** `peak in 45m` in the default dim text.
- **At all other times, weekends included:** no chip.
- **Countdown format:** the same as `cal-next`: `1h49m`, `49m`, `<1m`.
- **Clock:** the window follows America/Los_Angeles, like the site. The start
  is inclusive and the end is exclusive.

## Out of scope (YAGNI)

- A click popup, a weekly timeline, or notifications at the start and end. The
  site has these.
- US holidays. The site ignores them too.
- Plan awareness. ccflare reports `billingType: null` for every account.
- The i3blocks bar. The script speaks the i3blocks protocol, but
  `i3/i3blocks.conf` does not change.

## Why not ccflare's flag

ccflare's `/api/accounts` returns `peakHours.active` for each account. The
server computes it in `isAnthropicPeakHour`
(`packages/proxy/src/auto-refresh-scheduler.ts`), which hard-codes weekdays
13:00–19:00 UTC. That window matches 05:00–11:00 Pacific only
in winter (PST). In summer (PDT) it is 06:00–12:00 Pacific, one hour late. At
11:11 PDT on 2026-10-29, ccflare reported `active: true` and the site reported
off-peak. Also, the flag is gone when ccflare is unreachable. The chip uses
the clock instead.

## Approach

A bash blocklet, `i3/blocklets/claude_peak`, shown by the existing
`Blocklet.qml`. `worldclock` and `cal-next` use the same pattern.

Other options:

- **A pure QML component.** QML's JavaScript engine has no `Intl` (checked
  with `qml6`: `ReferenceError: Intl is not defined`). A QML chip must then
  hard-code the Pacific DST rules. The repo also has no QML test harness.
- **ccflare's `peakHours.active`.** See the section above.

### `i3/blocklets/claude_peak`

1. The script takes "now" from `CLAUDE_PEAK_NOW` (epoch seconds) if it is
   set, else from the clock. This is the test seam, like `WORLDCLOCK_NOW`.
2. It gets the weekday and the date in America/Los_Angeles. On Saturday and
   Sunday it prints empty lines.
3. It converts today's 05:00 and 11:00 Pacific to epochs with
   `TZ=America/Los_Angeles date -d`. tzdata handles DST. US clocks change on a
   Sunday at 02:00, so a change never falls inside a weekday window.
4. It prints the i3blocks lines: full_text, short_text, color.

| When (Pacific, Mon–Fri) | full_text | short_text | color |
|---|---|---|---|
| 05:00 ≤ now < 11:00 | `⚡ peak 49m` | `peak 49m` | `#f0c489` |
| 04:00 ≤ now < 05:00 | `peak in 45m` | `peak in 45m` | (none) |
| any other time | empty | empty | (none) |

The script does date math only. It uses no network and no secrets, and it
always exits 0.

### `quickshell/Bar.qml`

Add one `Blocklet` before `ClaudePool {}` in the top deck's right `Row`:

```qml
Blocklet {
    exec: Quickshell.shellDir + "/../i3/blocklets/claude_peak"
    interval: 30000
}
```

- The path is relative to `shellDir`, so a worktree build runs its own copy.
  `ClaudePool` does the same.
- `Blocklet` hides itself when full_text is empty. `Row` skips hidden items,
  so no gap stays behind.
- The chip refreshes every 30 s. The minute countdown is at most 30 s late.

### Docs

- `i3/blocklets/README.md`: add a `claude_peak` section.
- `quickshell/README.md`: name the chip in the `Bar.qml` and `Blocklet.qml`
  rows.

## Testing

`i3/blocklets/tests/test_claude_peak.sh` runs under `tests/run.sh`. Each case
pins `CLAUDE_PEAK_NOW` to a fixed UTC instant. The times below are Pacific.

| Day | Pacific time | Expected |
|---|---|---|
| Thu 2026-10-29 (PDT) | 10:11 | `⚡ peak 49m`, short `peak 49m`, color `#f0c489` |
| | 05:00 | `⚡ peak 6h0m` (start is inclusive) |
| | 10:59:30 | `⚡ peak <1m` |
| | 11:00 | no chip (end is exclusive) |
| | 11:11 | no chip (ccflare says peak here) |
| | 04:15 | `peak in 45m`, no color line |
| | 04:00 | `peak in 1h0m` |
| | 03:59 | no chip |
| Thu 2026-01-15 (PST) | 05:00 | `⚡ peak 6h0m` |
| | 04:30 | `peak in 30m` |
| | 11:00 | no chip |
| Sat 2026-10-31 (PDT) | 09:00 | no chip |
| Sun 2026-11-01 (PST) | 08:00 | no chip |
| Mon 2026-11-02 (PST) | 04:15 | `peak in 45m` |
| | 05:00 | `⚡ peak 6h0m` |

Two more checks:

- The host time zone does not leak: with `TZ=Asia/Tokyo` the output is the
  same.
- Without `CLAUDE_PEAK_NOW`, the script exits 0.

**Live check:** relaunch `qs` and take a screenshot of the bar. To see the
peak look outside peak hours, launch `qs` once with `CLAUDE_PEAK_NOW` set.
`Blocklet` processes inherit the environment of `qs`. Then relaunch `qs`
without it.
