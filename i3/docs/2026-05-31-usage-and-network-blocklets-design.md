# i3blocks: AI usage + adaptive network blocklets — design

**Date:** 2026-05-31
**Host:** hexane
**Repo:** `issmirnov/dotfiles` (public) — scripts live in `i3/blocklets/`, wired via `i3/i3blocks.conf`

## Goal

Add two things to the hexane i3blocks bar:

1. **AI usage** — Claude Code and Codex, each showing the rolling 5-hour window and
   the longer (7-day / weekly) window, verbose with reset countdowns. Two adjacent blocks.
2. **Network** — one adaptive block: quiet on wired LAN, loud (SSID + signal) on wifi,
   urgent when the link is down. Replaces the old `iface`/`wifi` blocklets, which are not
   wired into the active config (the reason the indicator feels stale/absent).

**Hard constraint:** the dotfiles repo is public. Committed scripts must contain **no
secrets**. OAuth tokens are read at runtime from files under `$HOME` that live outside the
repo; cache files live under `~/.cache/`.

## Data-source decision

Both providers expose the authoritative usage windows through the same private HTTP
endpoints their own UIs call (`/usage` in Claude Code, `/status` in Codex). Both were
**verified returning live data on hexane** during research.

Alternatives rejected:

- **Local-log estimate** (ccusage / Codex rollout JSONL): only estimates tokens/cost from
  local logs; cannot report the official percentages and under-reports usage incurred from
  the web app or other machines.
- **Cache the statusline payload** (have `statusline-command.sh` persist `rate_limits`): the
  payload is frequently absent for Max OAuth accounts (claude-code#40094) and is empty when
  no session is running — defeats a standalone block.

Used as a documented **fallback only** for Codex: the newest on-disk rollout snapshot.

## Component 1 — `blocklets/ai_usage`

One script, invoked twice via i3blocks `instance`, branching on `$BLOCK_INSTANCE`. Two
separate blocks (not one combined) so a failure in one provider never blanks the other and
each colors independently.

### Claude (`instance=claude`)

- **Request:** `GET https://api.anthropic.com/api/oauth/usage`
- **Token:** `jq -r '.claudeAiOauth.accessToken' ~/.claude/.credentials.json`
- **Headers (all required):**
  - `Authorization: Bearer <token>`
  - `anthropic-beta: oauth-2025-04-20`
  - `anthropic-version: 2023-06-01`
  - `User-Agent: claude-code/<ver>` — **load-bearing**; without it the endpoint returns
    sticky HTTP 429. Derive `<ver>` from `claude --version` (regex `[0-9]+\.[0-9]+\.[0-9]+`),
    fall back to a hardcoded recent version string.
- **Response fields:** `.five_hour.utilization` (float 0–100), `.five_hour.resets_at`
  (ISO-8601 string with offset), `.seven_day.utilization`, `.seven_day.resets_at`.
  (`.seven_day_opus` / `.seven_day_sonnet` exist but may be null — not displayed.)
- **Renders:** `CC 5h 10% 7d 67% ⚠️13 (3d4h)`
- **Weekly pace indicator** (`pace_sym`, weekly window only): goal is to consume ~100% of
  the weekly quota evenly (1/7 per day) without running out early or leaving tokens unused.
  Compute the even-pace target `expected = (elapsed / window) * 100` where `elapsed =
  window - remaining` (window = 604800s), then `delta = utilization - expected`, and render
  an emoji + the points off pace after the weekly percentage: `⚠️N` = N points **ahead**
  (burning hot — ease off or you'll run out early), `🦥N` = N points **behind** (under-using
  — speed up), `✅` = on pace (within ±5). Shown whenever a weekly reset time is known
  (independent of the ≥50% reset-countdown threshold). **Applies to both** the Claude 7d
  window and the Codex weekly window. The short 5-hour windows get no pace indicator —
  they're rolling limits, not consume-to-100% goals.

### Codex (`instance=codex`)

- **Request:** `GET https://chatgpt.com/backend-api/wham/usage`
- **Token:** `jq -r '.tokens.access_token' ~/.codex/auth.json`;
  **account:** `jq -r '.tokens.account_id' ~/.codex/auth.json`
- **Headers:**
  - `Authorization: Bearer <token>`
  - `ChatGPT-Account-Id: <account_id>`
  - `User-Agent: codex-cli`
- **Response fields:** `.rate_limit.primary_window.used_percent` (5h; `limit_window_seconds`
  18000), `.rate_limit.secondary_window.used_percent` (weekly; 604800). Each window has
  `reset_after_seconds` (countdown) and `reset_at` (epoch seconds). This read does not
  consume model quota.
- **Renders:** `CX 5h 3% wk 11% ✅` (weekly pace via the shared `pace_sym` — see above)
- **Fallback (no network / 401):** newest `~/.codex/sessions/*/*/*/rollout-*.jsonl`, last
  line containing `"rate_limits"`, fields `.payload.rate_limits.primary.used_percent` /
  `.secondary.used_percent`. This is a lagging snapshot and `rate_limits` may be null in some
  versions — scan backward and skip nulls; tolerate `resets_in_seconds` vs `resets_at` drift.

### Shared logic

- **Cache:** `~/.cache/i3blocks-aiusage/<provider>.json`. Render from cache when its mtime is
  within TTL (**Claude 180 s** — a hard floor on polling; Codex 120 s). Only hit the network
  when the cache is stale. This keeps Claude under its safe polling rate even if the block is
  signalled to refresh.
- **Color** (3rd output line; `markup=none` is set globally so color comes from this line,
  not pango): driven by the worst of that provider's two windows —
  green `#00C853` `<70`, yellow `#FFD600` `70–89`, red `#FF1744` `≥90`.
- **Reset countdown:** appended in parentheses per window that is `≥50%`, e.g. `(3d4h)`,
  `(4h2m)`, `(7m)`. Claude: parse ISO with `date -d`. Codex: use `reset_after_seconds`.
- **Failure handling** (any of: missing token file / curl error / non-2xx / 401-expired),
  in precedence order, all rendered in **gray `#888888`** to signal "not live":
  1. For Codex only: the newest on-disk rollout snapshot (above).
  2. The last cached value, regardless of age.
  3. If neither exists: `CC ?` / `CX ?`.

  The script **never refreshes the OAuth token** (a refresh rotates the token file and would
  race a live Claude session, invalidating it). The script always exits 0 so it can never
  break the bar.

### Config (`i3/i3blocks.conf`)

```ini
[network]
interval=10

[claude_usage]
command=$SCRIPT_DIR/ai_usage
instance=claude
interval=1200

[codex_usage]
command=$SCRIPT_DIR/ai_usage
instance=codex
interval=1200
```

Inserted just before `[time]`, so the resulting bar order (left→right) is the existing
`bt_vol, memory, cpu_usage, volume`, then `network, claude_usage, codex_usage`, then `time`.
`~/.i3blocks.conf` is a symlink to `i3/i3blocks.conf`, so editing the repo file is the
deployed change (no separate dotbot relink needed).

## Component 2 — `blocklets/network`

Keys off the **default route**, which sidesteps the ~60 docker/veth/bridge interfaces on
this host:

```sh
IF=$(ip route show default 2>/dev/null | awk '/^default/{print $5; exit}')
```

Decision tree:

1. **No `$IF`** (no default route) → `no net`, red `#FF1744`, **exit 33** (i3blocks urgent).
   Exit-33-as-urgent to be confirmed against installed i3blocks 1.5 during implementation; red
   color is the baseline regardless.
2. **`$IF` is `tun*`/`wg*`/`tap*`** → `VPN`, cyan `#00B8D4`. (A separate openvpn block exists;
   this only prevents a tunnel being mislabeled "LAN".)
3. **`/sys/class/net/$IF/wireless` exists** → **wifi** (the exception state — loud):
   - SSID: `nmcli -t -f active,ssid dev wifi | awk -F: '$1=="yes"{print $2; exit}'`
     (fallback `iw dev "$IF" link`). Handle the rare colon-in-SSID nmcli escaping.
   - Signal 0–100: `nmcli -t -f active,signal dev wifi | awk -F: '$1=="yes"{print $2; exit}'`.
   - Render `MyAP-5G 72%`; color yellow `#FFD600`, orange `#FF6D00` when signal `<40`.
4. **Otherwise** → **wired**: `LAN`, green `#00C853`. Quiet confirmation (no IP — display-only
   was chosen; IP remains available via `ip a` or a future click action).

`interval=10`. Optional future enhancement (noted, not built): a NetworkManager
`dispatcher.d` hook that signals i3blocks on connectivity change for instant switch-over.

Tooling confirmed present on hexane: `nmcli`, `iw`. Absent: `iwgetid`, `iwconfig` (do not use).

## Key-leakage safeguards

- Tokens read from `~/.claude/.credentials.json` and `~/.codex/auth.json` at runtime — never
  embedded in scripts, never written into the repo.
- Cache files in `~/.cache/i3blocks-aiusage/` — outside the repo.
- Only percentages, SSID, and reset times ever reach the bar — no tokens, IPs (wired), or
  account IDs.
- `i3/.gitignore` already excludes the generated `config`; blocklets and this doc are tracked
  as intended. The endpoint/header details recorded here are already public (GitHub
  issues / source), not secrets.

## Verification plan

- `BLOCK_INSTANCE=claude i3/blocklets/ai_usage` → `CC 5h NN% 7d NN% …`; same for `codex`.
- Failure path: temporarily rename a credential file → expect gray `CC ?`, exit 0.
- Claude polling: confirm no more than one network call per 180 s under normal bar operation
  (cache TTL enforces this).
- Network: with wired up → `LAN` green; `nmcli dev disconnect <eth>` or unplug → wifi or
  `no net`; confirm default-route detection never picks a docker/veth/bridge iface.
- Reload: `i3-msg reload` (or restart i3blocks) and eyeball the three new segments.

## Out of scope (YAGNI)

- Click actions (display-only was chosen).
- OAuth token refresh.
- Cost / historical-usage graphs (ccusage covers cost if ever wanted).
- Deleting the old GPL `iface`/`wifi` blocklets — left in place, just unreferenced.
