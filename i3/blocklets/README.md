# i3blocks blocklets

Scripts that render segments in the i3 bar via [i3blocks](https://github.com/vivien/i3blocks).
The bar's `status_command` sets `SCRIPT_DIR=~/.dotfiles/i3/blocklets`, so each `[name]`
block in [`../i3blocks.conf`](../i3blocks.conf) runs the matching script in this folder.
Each script prints the i3blocks 3-line protocol — `full_text`, `short_text`, `color`
(`#RRGGBB`); `markup=none` is set globally.

Most files here are stock [i3blocks-contrib](https://github.com/vivien/i3blocks-contrib)
scripts (`battery`, `cpu_usage`, `disk`, `memory`, `volume`, `iface`, `wifi`, …). The four
documented below — `ai_usage`, `network`, `worldclock`, and `claude_peak` — are custom.

> **Reload:** i3blocks only re-reads its config when the bar (re)starts. After editing
> `i3blocks.conf`, run **`i3-msg restart`** (in-place; windows/workspaces preserved). A
> plain `i3-msg reload` is *not* enough.

## `ai_usage` — Claude Code & Codex usage

One script, run twice via `instance`:

```ini
[claude_usage]
command=$SCRIPT_DIR/ai_usage
instance=claude
interval=1200

[codex_usage]
command=$SCRIPT_DIR/ai_usage
instance=codex
interval=1200
```

Shows the rolling **5-hour** and **weekly** usage windows for each provider, verbose with
reset countdowns and a weekly pace indicator:

```
CC 5h 10% 7d 67% ⚠️13 (3d4h)
CX 5h 3%  wk 11% ✅
```

### Data source

Claude comes from better-ccflare, which tracks every account in its pool; Codex reads the
same private endpoint its official UI uses (`/status`):

| Provider | Endpoint | Token (read at runtime) |
|----------|----------|-------------------------|
| Claude | `GET $CCFLARE_BASE/api/accounts` on better-ccflare (default `http://10.3.39.6:8080`): usage for every Anthropic account in the pool | Bearer token in `~/.config/ccflare/token` (`CCFLARE_TOKEN_FILE`) |
| Codex  | `GET https://chatgpt.com/backend-api/wham/usage` | `~/.codex/auth.json` → `.tokens.access_token` (+ `.account_id`) |

**No secrets live in this repo.** Tokens are read from `$HOME` at call time and never
written here; the response is cached in `~/.cache/i3blocks-aiusage/<provider>.json`. The
script **never refreshes** the OAuth token (read-only, so it can't race a live CLI
session) and always exits 0 so a failure can't break the bar. On error / expiry it shows
the last cached value dimmed gray, or `CC ?` / `CX ?` if there's nothing cached.

Claude's numbers come from better-ccflare, which polls Anthropic itself, so the Claude
cache TTL is only 60s; Codex's is 120s. Both floors hold regardless of the configured
`interval`.

### `__pool`: the ccflare fleet for Quickshell

`BLOCK_INSTANCE=claude ai_usage __pool` prints one JSON array that
`quickshell/ClaudePool.qml` turns into one chip per Anthropic account. It's sorted by
ccflare `priority` (lower first, ties by name); each object carries:

| Field | Meaning |
|-------|---------|
| `primary` | ccflare's `isPrimary`: the account the next request goes to |
| `blocked` | `reauth` / `paused` / `limited`, first match, mirroring ccflare's availability check; never set on the primary |
| `text`, `color` | the per-account chip text (🔑 / ⏸ / ⏳ after the tag when blocked) and its pct color |
| `worst` | max of the 5h and 7d utilization; drives the primary chip's fill |
| `status` | popup line, e.g. `primary · priority 1`, `paused (manual) · priority 11` |
| `stale` | the cache had expired and the fetch failed: `primary` forced off, color gray |

`ai_usage __poolrender [1]` renders JSON from stdin (`1` = stale); the tests use it.

### Weekly pace indicator

Goal: consume ~100% of the weekly quota evenly (≈1/7 per day) without running out early or
leaving tokens unused. The block compares your actual weekly usage to where even pacing
would put you right now (`expected = elapsed/window × 100`) and appends:

| Token | Meaning |
|-------|---------|
| `⚠️N` | N points **ahead** of pace — burning hot, ease off or you'll run out early |
| `🦥N` | N points **behind** — under-using, speed up |
| `✅`  | on pace (within ±5 points) |

Only the **weekly** window gets a pace token; the 5-hour window is a short rolling limit,
not a consume-to-100% goal.

### Color

The segment color reflects the **worst window's raw utilization**: green `<70`, yellow
`70–89`, red `≥90`. Color signals proximity to the hard limit; the emoji signals pace.

## `network` — adaptive network indicator

Single block (`[network]`, `interval=10`). Keys off the **default route**, so it ignores
the host's many docker / veth / bridge interfaces:

| State | Renders | Color |
|-------|---------|-------|
| Wired (preferred) | `LAN` | green |
| Wi-Fi | `<SSID> <signal>%` | yellow (orange if signal `<40`) |
| VPN (`tun*` / `wg*` / `tap*`) | `VPN` | cyan |
| No default route | `no net` | red (urgent — exit 33) |

SSID and signal come from `nmcli` (falling back to `iw`).

## `worldclock` — Zagreb / Prague / Kyiv

Single block (`[worldclock]`, `interval=30`). Live time in three cities, collapsing those
that currently share a clock:

```
ZAG·PRG 21:03  KYV 22:03
```

Zagreb and Prague are both Central European Time and always show the same clock; Kyiv is one
hour ahead (Eastern European Time). The grouping is computed from the *actual* rendered
times, so it's DST-aware and self-correcting — if two cities' clocks ever diverged they'd
split into separate labels automatically. `full_text` shows the labelled groups; `short_text`
drops the labels (`21:03 22:03`).

Pure `date`/`TZ` — no network, no secrets, always exits 0. The `WORLDCLOCK_NOW=<epoch>` seam
pins "now" so the summer/winter tests assert exact strings across a DST boundary.

## `claude_peak` — Claude peak hours

Claude's weekday peak hours: Monday to Friday, 05:00–11:00 `America/Los_Angeles`, the
window that [claude-peak-time.pages.dev](https://claude-peak-time.pages.dev/) shows. The
Quickshell bar shows it as a chip left of the Claude usage chips. `i3blocks.conf` has no
block for it.

| When (Pacific, Mon–Fri) | Renders | Color |
|-------------------------|---------|-------|
| 05:00–11:00 | `⚡ peak 49m` (time left) | amber `#f0c489` |
| 04:00–05:00 | `peak in 45m` | none (bar default) |
| any other time | nothing (block hidden) | |

The start is inclusive and the end is exclusive. The script follows Pacific time, not
ccflare's `peakHours.active`: ccflare hard-codes 13:00–19:00 UTC, one hour late during PDT.
Since 2026-05-06 the peak-hour cut no longer applies to Claude Code on Pro and Max
([Anthropic](https://www.anthropic.com/news/higher-limits-spacex)).

Pure `date`/`TZ`: no network, no secrets, always exits 0. The `CLAUDE_PEAK_NOW=<epoch>` seam
pins "now" so the tests cover both window edges in PDT and PST.

## Tests

Dependency-free bash harness (no `bats`/`shellcheck` required). All four custom scripts
expose env-var seams (`AIUSAGE_CACHE_DIR`, `AIUSAGE_NO_FETCH`, `AIUSAGE_ROLLOUT_FILE`,
`NET_TEST_IF`/`NET_TEST_WIRELESS`/`NET_TEST_SSID`/`NET_TEST_SIGNAL`, `WORLDCLOCK_NOW`,
`CLAUDE_PEAK_NOW`) and hidden dispatch verbs (`__color`, `__reset`, `__pace`, `__render`,
`__maprollout`) so every branch — thresholds, pace math, parsing, caching, fallbacks, all
network states, world-clock DST collapse, peak-hour edges — is testable offline against
synthetic fixtures (no live network or tokens needed).

```sh
bash tests/run.sh        # runs every tests/test_*.sh (skips on macOS)
```

## See also

Design notes and rationale (exact endpoints, verified response shapes, alternatives
considered): [`../docs/2026-05-31-usage-and-network-blocklets-design.md`](../docs/2026-05-31-usage-and-network-blocklets-design.md).
