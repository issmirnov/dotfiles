# ccflare-aware Claude usage chips — design

**Date:** 2026-10-27
**Status:** Approved in brainstorming — not yet built.
**Author:** Ivan + Claude

## Motivation

The bar's top-right cluster has three Claude usage chips, one per Anthropic
account in better-ccflare (`sl` = claude-smirnovlabs, `ig` = claude_isgmirnov,
`va` = claude-vaniaspeedy). Their order is hardcoded in `Bar.qml` (sl, ig, va)
and nothing marks which account ccflare is routing to. ccflare already knows
both things:

- `GET /api/accounts` returns `isPrimary` per account, "the account the load
  balancer would pick next". The server fills it from the active strategy's
  `peek()`. The ccflare dashboard's "Primary" badge reads the same flag.
- Each account has a `priority` (0–100, lower = preferred). Today:
  ig = 1, va = 2, sl = 11. With the `session` strategy, ccflare stays on the
  account holding the live 5h session unless a higher-priority account is
  available. So the primary is usually the highest-priority account that
  isn't blocked.

ccflare runs on puma LXC 106 (`http://10.3.39.6:8080`, v3.5.105 at time of
writing). The `ai_usage` blocklet already calls `/api/accounts` with the
Bearer token in `~/.config/ccflare/token`. No new credentials are needed.

## Decisions (locked in brainstorming)

- **Live priority order.** One fetch drives all Claude chips. They sort left to
  right by ccflare priority and re-sort when priorities change in the
  dashboard. Accounts added or renamed in ccflare appear without a `Bar.qml`
  edit.
- **The primary chip is a filled pill.** Pastel fill with dark text, like the
  CPU/MEM chips. The fill tracks that account's worse window (max of 5h and
  7d): mint below 70%, amber 70–89%, rose 90% and up, the same thresholds as
  the text color today. Standby chips keep today's look: dark pill, colored
  text.
- **Blocked standby chips are dimmed** (~55% opacity) and carry a glyph:
  ⏸ paused, ⏳ rate-limited, 🔑 needs re-auth.
- **The priority number appears only in the popup**, as a status line. The bar
  shows priority through chip order alone.
- **The codex chip and the i3blocks output stay as they are.**

## Out of scope (YAGNI)

- Changing priority or pausing accounts from the bar (ccflare exposes
  `POST /api/accounts/:id/priority`; a "make primary" click is a possible
  follow-up).
- Rank digits or raw priority numbers on the bar itself.
- ccflare's other signals: re-auth deadline warnings, usage throttling, peak
  hours, pool-level `/health` summary.
- Any change to i3blocks layout or the per-account `claude:<name>` rendering.

## Architecture

```
ccflare /api/accounts ──► ai_usage (cache, 60s TTL) ──► ai_usage __pool (JSON)
                                                             │
                              ClaudePool.qml (poll 30s) ◄────┘
                                │  Repeater over priority order
                                ▼
                         UsageChip (fed mode) × N ──click──► popup
                                                    (ai_usage __detail, as today)
```

### 1. `ai_usage __pool` (bash, `i3/blocklets/ai_usage`)

New verb. Loads the accounts JSON through the existing cache/fetch path and
prints one JSON array of the Anthropic accounts, sorted by `priority`
ascending, ties broken by `name`. Each entry:

| field | meaning |
|---|---|
| `name` | ccflare account name, e.g. `claude_isgmirnov` |
| `tag` | `short_tag` of the name, e.g. `ig` |
| `priority` | ccflare priority (int) |
| `primary` | ccflare `isPrimary`, forced `false` when `stale` |
| `blocked` | `reauth` \| `paused` \| `limited` \| `""` (see below) |
| `worst` | max of 5h and 7d utilization, int |
| `text` | today's per-account chip text (the `full_text` the `claude:<name>` instance renders), with the blocked glyph inserted after the tag: `CC ig ⏸ 100/58` |
| `color` | `pct_color(worst)`, or `#888888` when `stale` |
| `status` | popup status line, e.g. `primary · priority 1`, `standby #2 · priority 2` (#N = position in the sorted list), `paused (manual) · priority 11`, `rate-limited until Tue 14:05 · priority 2` (weekday included: a weekly-limit backoff can last days), `needs re-auth · priority 2`; when `stale`, `ccflare unreachable · priority N` |
| `stale` | `true` when ccflare couldn't be reached and the data is from an expired cache. It only forces `primary` off, the color gray and the stale status line; `blocked` and the glyphs still reflect the cached data |

`blocked` mirrors ccflare's own availability check (`isAccountAvailable`),
first match wins:

1. `requiresReauth` → `reauth` (🔑)
2. `paused` → `paused` (⏸); the status line names `pauseReason`
3. `rateLimitedUntil` (epoch ms) later than now → `limited` (⏳)

A primary chip never shows a blocked glyph. ccflare can flag a paused account
primary when it will auto-unpause it on the next request (auto-fallback after
its window reset). In that case `primary` wins and `blocked` is `""`.

Other changes in the script:

- Claude cache TTL drops from 180s to 60s, so an account switch reaches the bar
  within about 90s (60s TTL + 30s poll). The call only goes to ccflare on the
  LAN, never to Anthropic, so the extra polling is free. i3blocks polls every
  20 min and is unaffected.
- A stdin-fed twin, `__poolrender`, takes the JSON on stdin and staleness from
  an argument, so tests drive it without the network. This mirrors the
  existing `__render` verb.
- If no account data is available at all, `__pool` prints `[]`.

### 2. `ClaudePool.qml` (new)

A `Row` that replaces the three hardcoded `UsageChip { instance: "claude:…" }`
lines in `Bar.qml`.

- Runs `ai_usage __pool` every 30s (`triggeredOnStart`). The script path
  resolves relative to `Quickshell.shellDir`
  (`<shellDir>/../i3/blocklets/ai_usage`), so a worktree build runs its own
  script during QA. The kernel resolves `..` after following the
  `~/.config/quickshell` symlink, so the live bar still lands on
  `~/.dotfiles/i3/…`.
- Keeps two properties: `order` (array of names) and `byName` (name → entry).
  `byName` is replaced on every poll. `order` is reassigned only when the
  joined name list changes. The `Repeater` models `order`, so a routine
  refresh doesn't rebuild the chips or close an open popup.
- Each delegate is a `UsageChip` in fed mode, bound to `byName[modelData]`.
- When `order` is empty (no data, or unparseable output), shows one gray
  `CC ?` chip, same as today's failure state.

### 3. `UsageChip.qml` (changed)

- New `entry` property (the pool's JSON object). When set, the chip takes its
  text, color, primary and blocked state from it and its own blocklet
  `Process`/`Timer` stay off. Without `entry` it behaves exactly as now (the
  codex chip).
- Primary: `color` = `Theme.usageOk`/`usageWarn`/`usageCrit` by `entry.worst`,
  text = `Theme.chipText`, with a short `ColorAnimation` like `StatChip`.
- Blocked and not primary: `opacity` 0.55.
- Popup: `entry.status` as a subtitle line under the title. The meters still
  come from `ai_usage __detail` with `BLOCK_INSTANCE=claude:<name>`.

### 4. `Theme.qml` and `Bar.qml`

- `Theme`: three new tokens, `usageOk` (mint), `usageWarn` (amber),
  `usageCrit` (rose), with pastel and vivid values drawn from the existing
  palette.
- `Bar`: three `UsageChip` lines become `ClaudePool {}`; the comment above them
  is updated. `UsageChip { instance: "codex" }` stays.

## Error handling

| situation | bar shows |
|---|---|
| ccflare reachable | chips in priority order, primary filled |
| ccflare down, cache expired but present | same order, all chips gray, none filled |
| no cache and ccflare down | one gray `CC ?` chip |
| every account blocked (`isPrimary` false everywhere) | all chips dimmed with glyphs, none filled |
| an account added/removed/renamed in ccflare | chip set and order update on the next poll |

## Testing

- **Bash** (`i3/blocklets/tests/test_claude_pool.sh` + a fixture with ig/va/sl
  plus a non-Anthropic account):
  - sort by priority, tie-break by name
  - `primary` passed through
  - each blocked glyph and status line, including the first-match precedence
  - a paused-but-primary account stays lit with no ⏸
  - stale input → nothing primary, gray color
  - non-Anthropic accounts excluded
  - `text` matches the per-account `claude:<name>` full_text plus glyph

  The existing blocklet suite (`i3/blocklets/tests/run.sh`) must still pass.
- **QML** (from the worktree, before merge): stop the live `qs`, start
  `qs -p <worktree>/quickshell` via `hyprctl dispatch`, check `/tmp/qs.log`,
  screenshot the cluster. Then a second run with `AIUSAGE_CACHE_DIR` pointing
  at a fixture cache and `AIUSAGE_NO_FETCH=1`, to see amber and rose fills and
  a blocked chip. Touch the fixture file just before launching so it reads as
  fresh; past the 60s TTL it turns gray, which doubles as the stale-state
  check. Open a popup across a poll to confirm it stays open. Restore
  the live `qs` afterwards.

## Docs

- `i3/blocklets/README.md`: document `__pool` / `__poolrender`.
- KB `~/docs/docs/systems/hexane/hyprland-bars.md`: one bullet on the pool
  chips (separate repo, separate commit).
