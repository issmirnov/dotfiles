# i3blocks blocklets

Scripts that render segments in the i3 bar via [i3blocks](https://github.com/vivien/i3blocks).
The bar's `status_command` sets `SCRIPT_DIR=~/.dotfiles/i3/blocklets`, so each `[name]`
block in [`../i3blocks.conf`](../i3blocks.conf) runs the matching script in this folder.
Each script prints the i3blocks 3-line protocol — `full_text`, `short_text`, `color`
(`#RRGGBB`); `markup=none` is set globally.

Most files here are stock [i3blocks-contrib](https://github.com/vivien/i3blocks-contrib)
scripts (`battery`, `cpu_usage`, `disk`, `memory`, `volume`, `iface`, `wifi`, …). The two
documented below — `ai_usage` and `network` — are custom.

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

Reads the same private endpoints the official UIs use (Claude Code's `/usage`, Codex's
`/status`):

| Provider | Endpoint | OAuth token (read at runtime) |
|----------|----------|-------------------------------|
| Claude | `GET https://api.anthropic.com/api/oauth/usage` | `~/.claude/.credentials.json` → `.claudeAiOauth.accessToken` |
| Codex  | `GET https://chatgpt.com/backend-api/wham/usage` | `~/.codex/auth.json` → `.tokens.access_token` (+ `.account_id`) |

**No secrets live in this repo.** Tokens are read from `$HOME` at call time and never
written here; the response is cached in `~/.cache/i3blocks-aiusage/<provider>.json`. The
script **never refreshes** the OAuth token (read-only, so it can't race a live CLI
session) and always exits 0 so a failure can't break the bar. On error / expiry it shows
the last cached value dimmed gray, or `CC ?` / `CX ?` if there's nothing cached.

Claude's endpoint returns sticky `429`s without a `User-Agent: claude-code/<ver>` header
and shouldn't be polled faster than ~180s; the in-script cache TTL enforces that floor
regardless of the configured `interval`.

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

## Tests

Dependency-free bash harness (no `bats`/`shellcheck` required). Both custom scripts expose
env-var seams (`AIUSAGE_CACHE_DIR`, `AIUSAGE_NO_FETCH`, `AIUSAGE_ROLLOUT_FILE`,
`NET_TEST_IF`/`NET_TEST_WIRELESS`/`NET_TEST_SSID`/`NET_TEST_SIGNAL`) and hidden dispatch
verbs (`__color`, `__reset`, `__pace`, `__render`, `__maprollout`) so every branch —
thresholds, pace math, parsing, caching, fallbacks, all network states — is testable
offline against synthetic fixtures (no live network or tokens needed).

```sh
bash tests/run.sh        # runs every tests/test_*.sh
```

## See also

Design notes and rationale (exact endpoints, verified response shapes, alternatives
considered): [`../docs/2026-05-31-usage-and-network-blocklets-design.md`](../docs/2026-05-31-usage-and-network-blocklets-design.md).
