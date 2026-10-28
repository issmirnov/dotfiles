# ccflare-aware Claude usage chips Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sort the bar's Claude usage chips by better-ccflare priority and fill the chip of the account ccflare routes the next request to.

**Architecture:** A new `ai_usage __pool` verb turns one `/api/accounts` snapshot into a JSON array (sorted, with primary/blocked/status per account). A new `ClaudePool.qml` polls it and drives a `Repeater` of `UsageChip`s in a new "fed" mode; the codex chip and i3blocks output are untouched.

**Tech Stack:** bash + jq + curl (blocklet), Quickshell 0.3.2 QML (Qt6), dependency-free bash test harness (`i3/blocklets/tests/assert.sh`).

**Spec:** `docs/superpowers/specs/2026-10-27-ccflare-claude-pool-chips-design.md`

## Global Constraints

- Worktree: `/home/vania/.dotfiles-worktrees/claude-pool-chips`, branch `feat/claude-pool-chips` off `origin/master`. All paths below are relative to it unless absolute.
- Stage only the files a task names; never `git add -A`. The main checkout `/home/vania/.dotfiles` has the user's uncommitted `hypr/hyprland.lua`: don't touch it.
- No secrets in the repo: the ccflare token stays in `~/.config/ccflare/token`; never print it.
- Sort: ccflare `priority` ascending, ties by `name`. Fill thresholds: mint `<70`, amber `70–89`, rose `>=90` of `worst` = max(5h, 7d).
- Blocked, first match wins: `requiresReauth` → `reauth` 🔑; `paused` → `paused` ⏸; `rateLimitedUntil` (epoch ms) > now → `limited` ⏳. The primary is never blocked.
- Stale (expired cache, fetch failed): `primary` false, color `#888888`, status `ccflare unreachable · priority N`; `blocked` and glyphs keep the cached state.
- Claude cache TTL 60s (was 180s); ClaudePool polls every 30s. Codex TTL stays 120s.
- `ai_usage` must keep exiting 0 and keep its existing verbs' output byte-identical.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Agent shell quirks: `cp` is interactive in zsh (use `command cp -f`), `noclobber` is on (use `>|`), launch GUI processes via `hyprctl dispatch 'hl.dsp.exec_cmd("…")'` (direct spawns get killed), match qs with `pkill -x qs` (never `pkill -f`).

---

### Task 1: `ai_usage __pool` / `__poolrender` + 60s Claude TTL

**Files:**
- Create: `i3/blocklets/tests/fixtures/claude_ccflare_pool.json`
- Create: `i3/blocklets/tests/test_claude_pool.sh`
- Modify: `i3/blocklets/ai_usage` (header comment, new `cache_ttl`, `load_json` + `main` TTL lines, new `render_pool` + `pool_main`, dispatch)
- Modify: `i3/blocklets/README.md` (`ai_usage` section)

**Interfaces:**
- Consumes: existing `short_tag`, `pct_color`, `render_claude` (reads global `ACCT`), `load_json`, globals `PROVIDER`, `CACHE_DIR`.
- Produces: `BLOCK_INSTANCE=claude ai_usage __pool` → one line, a JSON array of
  `{name, tag, priority, primary, blocked, worst, text, color, status, stale}`
  (types: string, string, number, bool, string, number, string, string, string, bool);
  `[]` when there's nothing. `ai_usage __poolrender [1]` renders stdin JSON (`1` = stale).

- [ ] **Step 1: Write the fixture**

`i3/blocklets/tests/fixtures/claude_ccflare_pool.json` (zeta precedes vaniaspeedy at the same priority so only the name tie-break puts va first; sl's 7d 2.4 exercises float truncation; omega's `rateLimitedUntil` is in the past):

```json
[
  {"name": "lena-chatgpt", "provider": "codex", "priority": 0, "isPrimary": false, "paused": false},
  {"name": "claude-zeta", "provider": "anthropic", "priority": 2, "isPrimary": false,
   "paused": true, "pauseReason": "manual", "requiresReauth": true, "rateLimitedUntil": null,
   "usageData": {"five_hour": {"utilization": 0, "resets_at": null}, "seven_day": {"utilization": 0, "resets_at": null}}},
  {"name": "claude-smirnovlabs", "provider": "anthropic", "priority": 11, "isPrimary": false,
   "paused": true, "pauseReason": "manual", "requiresReauth": false, "rateLimitedUntil": 1000,
   "usageData": {"five_hour": {"utilization": 0, "resets_at": null}, "seven_day": {"utilization": 2.4, "resets_at": null}}},
  {"name": "claude-vaniaspeedy", "provider": "anthropic", "priority": 2, "isPrimary": true,
   "paused": false, "pauseReason": null, "requiresReauth": false, "rateLimitedUntil": null,
   "usageData": {"five_hour": {"utilization": 75, "resets_at": null}, "seven_day": {"utilization": 29, "resets_at": null}}},
  {"name": "claude_isgmirnov", "provider": "anthropic", "priority": 1, "isPrimary": false,
   "paused": false, "pauseReason": null, "requiresReauth": false, "rateLimitedUntil": 4102444800000,
   "usageData": {"five_hour": {"utilization": 100, "resets_at": null}, "seven_day": {"utilization": 58, "resets_at": null}}},
  {"name": "claude-omega", "provider": "anthropic", "priority": 20, "isPrimary": false,
   "paused": false, "pauseReason": null, "requiresReauth": false, "rateLimitedUntil": 1000,
   "usageData": {"five_hour": {"utilization": 10, "resets_at": null}, "seven_day": {"utilization": 30, "resets_at": null}}}
]
```

- [ ] **Step 2: Write the failing test**

`i3/blocklets/tests/test_claude_pool.sh` (4102444800000 ms = Fri 2100-01-01 00:00 UTC):

```bash
#!/usr/bin/env bash
DIR=$(dirname "$0"); . "$DIR/assert.sh"; S="$DIR/../ai_usage"
F="$DIR/fixtures/claude_ccflare_pool.json"
# field <account> <key> <json>: one account's field from a __pool array
field() { jq -r --arg n "$1" --arg k "$2" '.[] | select(.name==$n) | .[$k]' <<<"$3"; }
nprimary() { jq '[.[] | select(.primary)] | length' <<<"$1"; }

out=$(TZ=UTC BLOCK_INSTANCE=claude bash "$S" __poolrender < "$F")

# --- order: ccflare priority ascending, ties by name; non-Anthropic accounts dropped ---
assert_eq "priority order, name tie-break, codex dropped" \
  "claude_isgmirnov claude-vaniaspeedy claude-zeta claude-smirnovlabs claude-omega" \
  "$(jq -r '[.[].name] | join(" ")' <<<"$out")"
assert_eq "priority passed through" "11" "$(field claude-smirnovlabs priority "$out")"
assert_eq "tag"                     "ig" "$(field claude_isgmirnov tag "$out")"

# --- primary: ccflare's isPrimary; text = the per-account chip text ---
assert_eq "va primary"            "true"                 "$(field claude-vaniaspeedy primary "$out")"
assert_eq "exactly one primary"   "1"                    "$(nprimary "$out")"
assert_eq "va status"             "primary · priority 2" "$(field claude-vaniaspeedy status "$out")"
assert_eq "va worst = max(5h,7d)" "75"                   "$(field claude-vaniaspeedy worst "$out")"
assert_eq "va color amber"        "#FFD600"              "$(field claude-vaniaspeedy color "$out")"
assert_eq "va not stale"          "false"                "$(field claude-vaniaspeedy stale "$out")"
va_solo=$(BLOCK_INSTANCE=claude:claude-vaniaspeedy bash "$S" __render < "$F" | sed -n 1p)
assert_eq "va text = per-account full_text" "$va_solo" "$(field claude-vaniaspeedy text "$out")"

# --- blocked standbys: glyph after the tag + status line; first match wins ---
assert_eq "ig limited"   "limited"                                   "$(field claude_isgmirnov blocked "$out")"
assert_eq "ig text"      "CC ig ⏳ 100/58"                            "$(field claude_isgmirnov text "$out")"
assert_eq "ig status"    "rate-limited until Fri 00:00 · priority 1" "$(field claude_isgmirnov status "$out")"
assert_eq "ig color red" "#FF1744"                                   "$(field claude_isgmirnov color "$out")"
assert_eq "zeta: reauth beats paused" "reauth"                       "$(field claude-zeta blocked "$out")"
assert_eq "zeta text"    "CC ze 🔑 0/0"                               "$(field claude-zeta text "$out")"
assert_eq "zeta status"  "needs re-auth · priority 2"                "$(field claude-zeta status "$out")"
assert_eq "sl paused"    "paused"                                    "$(field claude-smirnovlabs blocked "$out")"
assert_eq "sl text, 7d 2.4 truncated" "CC sl ⏸ 0/2"                  "$(field claude-smirnovlabs text "$out")"
assert_eq "sl status names the reason" "paused (manual) · priority 11" "$(field claude-smirnovlabs status "$out")"
assert_eq "omega: past rate limit is not blocked" ""                 "$(field claude-omega blocked "$out")"
assert_eq "omega standby = list position" "standby #5 · priority 20" "$(field claude-omega status "$out")"
assert_eq "omega text untouched" "CC om 10/30"                       "$(field claude-omega text "$out")"
assert_eq "omega green"  "#00C853"                                   "$(field claude-omega color "$out")"

# --- paused-but-primary (ccflare will auto-unpause it): stays lit, no ⏸ ---
pp=$(jq '(.[] | select(.name=="claude-vaniaspeedy")) |= (.paused=true | .pauseReason="overage")' "$F" \
  | BLOCK_INSTANCE=claude bash "$S" __poolrender)
assert_eq "paused primary stays primary" "true"        "$(field claude-vaniaspeedy primary "$pp")"
assert_eq "paused primary not blocked"   ""            "$(field claude-vaniaspeedy blocked "$pp")"
assert_eq "paused primary has no glyph"  "CC va 75/29" "$(field claude-vaniaspeedy text "$pp")"

# --- stale (expired cache, ccflare down): nothing lit, gray, glyphs kept ---
st=$(BLOCK_INSTANCE=claude bash "$S" __poolrender 1 < "$F")
assert_eq "stale: nothing primary" "0"                                "$(nprimary "$st")"
assert_eq "stale: gray"            "#888888"                          "$(field claude-vaniaspeedy color "$st")"
assert_eq "stale: flag"            "true"                             "$(field claude-vaniaspeedy stale "$st")"
assert_eq "stale: status"          "ccflare unreachable · priority 2" "$(field claude-vaniaspeedy status "$st")"
assert_eq "stale: glyph kept"      "CC sl ⏸ 0/2"                       "$(field claude-smirnovlabs text "$st")"

# --- degenerate input -> [] ---
assert_eq "empty array"  "[]" "$(echo '[]'               | BLOCK_INSTANCE=claude bash "$S" __poolrender)"
assert_eq "garbage"      "[]" "$(echo 'not json'         | BLOCK_INSTANCE=claude bash "$S" __poolrender)"
assert_eq "error object" "[]" "$(echo '{"type":"error"}' | BLOCK_INSTANCE=claude bash "$S" __poolrender)"

# --- __pool: cache/fetch path; stale only when the cache had expired and wasn't refreshed ---
TMP=$(mktemp -d); cp "$F" "$TMP/claude.json"
live=$(AIUSAGE_CACHE_DIR="$TMP" AIUSAGE_NO_FETCH=1 BLOCK_INSTANCE=claude bash "$S" __pool)
assert_eq "fresh cache: primary lit" "true"  "$(field claude-vaniaspeedy primary "$live")"
assert_eq "fresh cache: not stale"   "false" "$(field claude-vaniaspeedy stale "$live")"
touch -d '2 minutes ago' "$TMP/claude.json"     # past the 60s TTL, inside the old 180s one
old=$(AIUSAGE_CACHE_DIR="$TMP" AIUSAGE_NO_FETCH=1 BLOCK_INSTANCE=claude bash "$S" __pool)
assert_eq "expired cache: stale"     "true"  "$(field claude-vaniaspeedy stale "$old")"
assert_eq "expired cache: unlit"     "0"     "$(nprimary "$old")"
TMP2=$(mktemp -d)
assert_eq "no cache: []" "[]" "$(AIUSAGE_CACHE_DIR="$TMP2" AIUSAGE_NO_FETCH=1 BLOCK_INSTANCE=claude bash "$S" __pool)"
rm -rf "$TMP" "$TMP2"
finish
```

- [ ] **Step 3: Run it to verify it fails**

Run: `bash i3/blocklets/tests/test_claude_pool.sh`
Expected: many `FAIL` lines (the unknown verbs fall through to `main`, which prints i3blocks text, not JSON), ending `N passed, M failed` with M > 0.

- [ ] **Step 4: Implement in `i3/blocklets/ai_usage`**

4a. Header, after the `#   codex  -> …` line:

```bash
#   __pool -> the claude fleet as JSON for quickshell's ClaudePool.qml (see render_pool).
```

4b. Add above `load_json()` (after the `render_codex` function):

```bash
# Cache TTL in seconds. Claude reads better-ccflare on the LAN (ccflare polls Anthropic
# itself), so a short TTL is free and keeps the bar's primary-account cue current.
cache_ttl() { case "$PROVIDER" in codex) echo 120;; *) echo 60;; esac; }
```

4c. In `load_json()` replace `  case "$PROVIDER" in codex) ttl=120;; *) ttl=180;; esac` with `  ttl=$(cache_ttl)`. In `main()` replace `  case "$provider" in codex) ttl=120;; *) ttl=180;; esac` with `  ttl=$(cache_ttl)`.

4d. Add after `detail_codex()` (before `main()`):

```bash
# The claude fleet as JSON for quickshell's ClaudePool.qml: one object per Anthropic account,
# sorted by ccflare priority (lower = preferred), ties by name. `primary` is ccflare's
# isPrimary (where the next request goes). `blocked` mirrors ccflare's availability check,
# first match wins: requiresReauth -> reauth, paused -> paused, rateLimitedUntil (epoch ms)
# still ahead -> limited. The primary is never blocked: ccflare flags a paused account
# primary when it will auto-unpause it. `text` = the per-account chip text with the glyph
# after the tag. $2=1 marks the data stale (expired cache, ccflare unreachable): nothing
# primary, gray, "ccflare unreachable"; blocked/glyphs keep the cached state.
# Input: raw /api/accounts JSON. Output: one JSON array line ([] when there's nothing).
render_pool() {
  local json=$1 stale=${2:-0} now_ms pos=0 rows="" name prio isprim reauth paused reason rl_until
  local five sev tag worst blocked glyph primary status full pre text color stale_b=false
  now_ms=$(( $(date +%s) * 1000 ))
  [ "$stale" = 1 ] && stale_b=true
  # NOTE: "null" (not "") for absent fields — a `read` over @tsv collapses empty middle fields.
  while IFS=$'\t' read -r name prio isprim reauth paused reason rl_until five sev; do
    [ -z "$name" ] && continue
    pos=$(( pos + 1 ))
    tag=$(short_tag "$name")
    five=${five%.*}; sev=${sev%.*}
    worst=$five; [ "$sev" -gt "$worst" ] && worst=$sev
    blocked=""; glyph=""
    if [ "$isprim" != "true" ]; then
      if   [ "$reauth" = "true" ]; then blocked=reauth; glyph="🔑"
      elif [ "$paused" = "true" ]; then blocked=paused; glyph="⏸"
      elif [ "$rl_until" != "null" ] && [ "${rl_until%.*}" -gt "$now_ms" ]; then blocked=limited; glyph="⏳"
      fi
    fi
    primary=false; [ "$isprim" = "true" ] && [ "$stale" != 1 ] && primary=true
    if   [ "$stale" = 1 ];        then status="ccflare unreachable"
    elif [ "$primary" = "true" ]; then status="primary"
    else
      case "$blocked" in
        reauth)  status="needs re-auth" ;;
        paused)  status="paused"; [ "$reason" != "null" ] && status="paused ($reason)" ;;
        limited) status="rate-limited until $(date -d "@$(( ${rl_until%.*} / 1000 ))" '+%a %H:%M')" ;;
        *)       status="standby #$pos" ;;
      esac
    fi
    status="$status · priority $prio"
    full=$(ACCT=$name render_claude "$json" | sed -n 1p)
    pre="CC $tag "; text=$full
    [ -n "$glyph" ] && text="$pre$glyph ${full#"$pre"}"
    if [ "$stale" = 1 ]; then color="#888888"; else color=$(pct_color "$worst"); fi
    rows+=$(jq -cn --arg name "$name" --arg tag "$tag" --argjson priority "$prio" \
        --argjson primary "$primary" --arg blocked "$blocked" --argjson worst "$worst" \
        --arg text "$text" --arg color "$color" --arg status "$status" --argjson stale "$stale_b" \
        '{name:$name, tag:$tag, priority:$priority, primary:$primary, blocked:$blocked,
          worst:$worst, text:$text, color:$color, status:$status, stale:$stale}')$'\n'
  done < <(jq -r '
      [ .[]? | objects | select(.provider=="anthropic") ]
      | sort_by([ (.priority // 0), .name ]) | .[]
      | [ .name, (.priority // 0), (.isPrimary // false), (.requiresReauth // false),
          (.paused // false),
          ((.pauseReason // "") | if . == "" then "null" else . end),
          (.rateLimitedUntil // "null"),
          (.usageData.five_hour.utilization // 0),
          (.usageData.seven_day.utilization // 0) ] | @tsv
    ' <<<"$json" 2>/dev/null)
  jq -cs . <<<"$rows"
}

# __pool: load the claude fleet like main() (fresh cache, else fetch, else expired cache)
# and render it. Stale = the cache was already past its TTL before load_json AND load_json
# didn't rewrite it, i.e. the fetch failed and it served the expired copy.
pool_main() {
  local cache="$CACHE_DIR/$PROVIDER.json" now m0 m1 json stale=0
  now=$(date +%s); m0=$(stat -c %Y "$cache" 2>/dev/null || echo 0)
  json=$(load_json) || json="[]"
  m1=$(stat -c %Y "$cache" 2>/dev/null || echo 0)
  [ $(( now - m0 )) -ge "$(cache_ttl)" ] && [ "$m1" = "$m0" ] && stale=1
  render_pool "$json" "$stale"
}
```

4e. Dispatch: add two cases right after the `__detail)` case:

```bash
  __pool)       pool_main; exit 0 ;;
  __poolrender) render_pool "$(cat)" "${2:-0}"; exit 0 ;;
```

- [ ] **Step 5: Run the new test, then the whole suite**

Run: `bash i3/blocklets/tests/test_claude_pool.sh && bash i3/blocklets/tests/run.sh`
Expected: `test_claude_pool.sh` ends `N passed, 0 failed`; `run.sh` exits 0 with every file `… passed, 0 failed` (the existing `test_ai_fallback.sh` still passes: it uses a fresh copy and a 1-hour-old cache, both unaffected by the TTL change).

- [ ] **Step 6: Smoke-test against the real ccflare (read-only)**

Run: `BLOCK_INSTANCE=claude bash i3/blocklets/ai_usage __pool | jq -c '.[] | {name, priority, primary, blocked, text, status, stale}'`
Expected: the three live accounts in priority order (ig, va, sl today), exactly one `primary: true`, `stale: false`.

- [ ] **Step 7: Update `i3/blocklets/README.md`**

In the "Data source" table replace the Claude row with:

```markdown
| Claude | `GET $CCFLARE_BASE/api/accounts` on better-ccflare (default `http://10.3.39.6:8080`): usage for every Anthropic account in the pool | Bearer token in `~/.config/ccflare/token` (`CCFLARE_TOKEN_FILE`) |
```

Replace the paragraph starting "Claude's endpoint returns sticky `429`s" with:

```markdown
Claude's numbers come from better-ccflare, which polls Anthropic itself, so the Claude
cache TTL is only 60s; Codex's is 120s. Both floors hold regardless of the configured
`interval`.
```

Append a subsection before `### Weekly pace indicator`:

```markdown
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
```

- [ ] **Step 8: Commit**

```bash
git add i3/blocklets/ai_usage i3/blocklets/README.md i3/blocklets/tests/test_claude_pool.sh i3/blocklets/tests/fixtures/claude_ccflare_pool.json
git commit -m "ai_usage: __pool verb with ccflare priority order + primary account

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: `ClaudePool.qml` + fed `UsageChip` + Theme fills, wired into the bar

**Files:**
- Create: `quickshell/ClaudePool.qml`
- Modify: `quickshell/UsageChip.qml`
- Modify: `quickshell/Theme.qml` (three color tokens + `usageFill()`)
- Modify: `quickshell/Bar.qml` (right Row: three claude `UsageChip`s → `ClaudePool {}`)
- Modify: `quickshell/README.md` (file map)

**Interfaces:**
- Consumes: `ai_usage __pool` (Task 1) row shape `{name, tag, priority, primary, blocked, worst, text, color, status, stale}`; `ai_usage __detail` with `BLOCK_INSTANCE=claude:<name>` (existing).
- Produces: `Theme.usageOk/usageWarn/usageCrit` (color), `Theme.usageFill(pct) → color`; `UsageChip.entry` (var, default `null`; set → fed mode); `ClaudePool` (Row; properties `exec`, `interval`, `order`, `byName`, `loaded`).

- [ ] **Step 1: Theme tokens**

In `quickshell/Theme.qml`, after the `scratchBadge` line:

```qml

    // --- Claude usage chips: fill of the ccflare primary account's chip (ClaudePool →
    // UsageChip), by its worse window. ai_usage's pct_color thresholds in pastel, so the
    // dark chipText stays readable: mint <70 · amber 70–89 · rose ≥90.
    readonly property color usageOk:   _v ? "#3fae6a" : "#a2f0c8"
    readonly property color usageWarn: _v ? "#e0973b" : "#f0c489"
    readonly property color usageCrit: _v ? "#f7768e" : "#f0a2b8"
```

After the closing `}` of `heatColor(t)`:

```qml

    // Fill for a usage chip at `pct` (0–100) — see usageOk/usageWarn/usageCrit.
    function usageFill(pct) {
        if (pct >= 90) return usageCrit;
        if (pct >= 70) return usageWarn;
        return usageOk;
    }
```

- [ ] **Step 2: Fed mode in `quickshell/UsageChip.qml`**

Header comment: append these lines after the existing 4-line comment:

```qml
// Fed mode: ClaudePool.qml sets `entry` (one `ai_usage __pool` row) and the chip runs no
// blocklet of its own; the ccflare primary gets a pastel fill, blocked standbys dim.
```

Replace the property block + chip geometry (from `property int interval: 60000` through `visible: fullText !== ""`) with:

```qml
    property int interval: 60000
    property var entry: null                // ClaudePool row (text,color,primary,blocked,worst,status); null = run own blocklet

    property string fullText: entry ? (entry.text || "") : ""
    property string emittedColor: entry ? (entry.color || "") : ""
    property var detail: ({})               // parsed `ai_usage __detail` JSON: {title, windows:[…]}
    readonly property bool primary: !!(entry && entry.primary)
    readonly property bool blocked: !!(entry && !entry.primary && entry.blocked)

    height: Theme.chipHeight
    width: t.width + 18
    radius: Theme.chipRadius
    color: primary ? Theme.usageFill(entry.worst || 0) : Theme.surface
    Behavior on color { ColorAnimation { duration: 300 } }
    opacity: blocked ? 0.55 : 1
    visible: fullText !== ""
```

Change the comment `// ---- chip text + color: run the blocklet on a timer (mirrors Blocklet.qml) ----` to `// ---- chip text + color: run the blocklet on a timer (mirrors Blocklet.qml); off when fed ----`, and in the Timer that follows it change `running: true` to `running: chip.entry === null`.

Text `t` color becomes:

```qml
        color: chip.primary ? Theme.chipText
             : chip.emittedColor !== "" ? chip.emittedColor : Theme.subtext
```

In the popup body, replace the title `Text { … }` (the one with `text: chip.detail.title || chip.fullText`) with:

```qml
                Column {                            // title + (fed chips) the ccflare state line
                    width: parent.width
                    spacing: 2

                    Text {
                        width: parent.width
                        text: chip.detail.title || chip.fullText
                        color: chip.emittedColor !== "" ? chip.emittedColor : Theme.text
                        font.pixelSize: Theme.fontSize
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        visible: text !== ""
                        text: chip.entry ? (chip.entry.status || "") : ""
                        color: Theme.subtext
                        font.pixelSize: 13
                        elide: Text.ElideRight
                    }
                }
```

- [ ] **Step 3: Create `quickshell/ClaudePool.qml`**

```qml
import Quickshell
import Quickshell.Io
import QtQuick

// The better-ccflare Claude fleet: one UsageChip per Anthropic account, left→right in
// ccflare priority order (lower number first). The account ccflare sends the next request
// to (isPrimary) is filled; blocked standbys dim with 🔑/⏸/⏳. One `ai_usage __pool` call
// per poll returns the whole fleet, so order, primary and usage share one snapshot.
Row {
    id: pool
    spacing: Theme.gap

    // Relative to the shell dir so a worktree build (`qs -p <wt>/quickshell`) runs its own
    // script. The kernel resolves `..` after following the ~/.config/quickshell symlink, so
    // the live bar lands on ~/.dotfiles/i3/blocklets/ai_usage.
    property string exec: Quickshell.shellDir + "/../i3/blocklets/ai_usage"
    property int interval: 30000

    property var order: []          // account names in priority order; reassigned only on change
    property var byName: ({})       // name -> __pool row; replaced every poll
    property bool loaded: false     // a poll has finished (gates the "CC ?" placeholder)

    function apply(rows) {
        var m = {}, names = [];
        for (var i = 0; i < rows.length; i++) {
            m[rows[i].name] = rows[i];
            names.push(rows[i].name);
        }
        byName = m;                                 // surviving chips rebind in place
        if (names.join("\n") !== order.join("\n"))
            order = names;                          // rebuilds the chips (closes an open popup)
        loaded = true;
    }

    Process {
        id: proc
        command: ["/usr/bin/env", "BLOCK_INSTANCE=claude", pool.exec, "__pool"]
        stdout: StdioCollector {
            onStreamFinished: {
                var rows = [];
                try {
                    var o = JSON.parse(text);
                    if (Array.isArray(o))
                        rows = o;
                } catch (e) {}
                pool.apply(rows);
            }
        }
    }
    Timer {
        interval: pool.interval
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: proc.running = true
    }

    Repeater {
        model: pool.order
        UsageChip {
            required property string modelData
            instance: "claude:" + modelData
            exec: pool.exec
            entry: pool.byName[modelData] || ({})
        }
    }

    // nothing from ccflare and nothing cached: one gray chip, like the blocklet's "CC ?"
    UsageChip {
        visible: pool.loaded && pool.order.length === 0
        instance: "claude"
        exec: pool.exec
        entry: ({ text: "CC ?", color: "#888888" })
    }
}
```

- [ ] **Step 4: Wire into `quickshell/Bar.qml`**

Replace:

```qml
                // One chip per Anthropic account so each carries its own color (sl can be
                // red while ig stays green). `claude:<name>` renders + colors that account
                // solo; a bare "claude" would bundle them all under the single worst color.
                // Each usage chip drops down a 5h + weekly meter popup on click (UsageChip.qml).
                UsageChip { instance: "claude:claude-smirnovlabs" }
                UsageChip { instance: "claude:claude_isgmirnov" }
                UsageChip { instance: "claude:claude-vaniaspeedy" }
                UsageChip { instance: "codex" }
```

with:

```qml
                // One chip per ccflare Anthropic account, each with its own color (sl can be
                // red while ig stays green), left→right in ccflare priority order; the account
                // ccflare routes the next request to is filled (ClaudePool.qml). Each usage
                // chip drops down a 5h + weekly meter popup on click (UsageChip.qml).
                ClaudePool {}
                UsageChip { instance: "codex" }
```

- [ ] **Step 5: README file map**

In `quickshell/README.md`, change the `Blocklet.qml` row's `(worldclock, \`ai_usage\`)` to `(worldclock)` and add after it:

```markdown
| `ClaudePool.qml` | The better-ccflare Claude fleet: one `UsageChip` per Anthropic account from `ai_usage __pool`, in ccflare priority order; the account ccflare routes to next is filled, blocked ones dim. |
| `UsageChip.qml` | A Claude/Codex usage chip with a 5h + weekly meter popup; runs its own `ai_usage` instance, or is fed a row by `ClaudePool`. |
```

- [ ] **Step 6: QA on the real bar, live data (worktree build)**

```bash
ls -la /home/vania/.dotfiles-worktrees/claude-pool-chips/quickshell/../i3/blocklets/ai_usage   # the path ClaudePool resolves
pkill -x qs; hyprctl dispatch 'hl.dsp.exec_cmd("qs -p /home/vania/.dotfiles-worktrees/claude-pool-chips/quickshell >/tmp/qs-wt.log 2>&1")'
```

Wait ~3 s, then: `grep -iE 'error|warning|invalid|not a type|undefined' /tmp/qs-wt.log` (expected: nothing beyond the benign `sni.watcher` line) and `grep -c 'Configuration Loaded' /tmp/qs-wt.log` (≥1). Screenshot: `grim -o DP-1 -t png /tmp/b.png && magick /tmp/b.png -crop 1900x92+1940+0 +repage /tmp/c.png`, view `/tmp/c.png`.
Expected: Claude chips in order ig, va, sl; the primary (ig today) filled mint with dark text; the others as before; codex chip unchanged after them.

- [ ] **Step 7: QA all states from the fixture**

```bash
mkdir -p /tmp/qs-pool-fixture && command cp -f /home/vania/.dotfiles-worktrees/claude-pool-chips/i3/blocklets/tests/fixtures/claude_ccflare_pool.json /tmp/qs-pool-fixture/claude.json && touch /tmp/qs-pool-fixture/claude.json
pkill -x qs; hyprctl dispatch 'hl.dsp.exec_cmd("env AIUSAGE_CACHE_DIR=/tmp/qs-pool-fixture AIUSAGE_NO_FETCH=1 qs -p /home/vania/.dotfiles-worktrees/claude-pool-chips/quickshell >/tmp/qs-wt.log 2>&1")'
```

Within 60 s screenshot as in Step 6. Expected: `CC ig ⏳ 100/58` dimmed red text · `CC va 75/29` amber fill · `CC ze 🔑 0/0` dimmed · `CC sl ⏸ 0/2` dimmed · `CC om 10/30` normal green text. Click the va chip (hypr-cua `screenshot` → `click`) and confirm the popup shows `primary · priority 2` under the title. Then rose: `jq '(.[] | select(.name=="claude-vaniaspeedy")).usageData.five_hour.utilization = 92' /tmp/qs-pool-fixture/claude.json >| /tmp/qs-pool-fixture/x && mv -f /tmp/qs-pool-fixture/x /tmp/qs-pool-fixture/claude.json`, wait ≤ 35 s, screenshot: va now rose. Stale: wait until the file is > 60 s old (no touch), wait for the next poll, screenshot: every chip gray, none filled.

- [ ] **Step 8: Popup survives a poll; restore the worktree build on live data**

Relaunch as in Step 6 (live data). Open the primary chip's popup, wait 35 s (one poll), screenshot: popup still open with `primary · priority 1`. Click away to close.

- [ ] **Step 9: Commit**

```bash
git add quickshell/ClaudePool.qml quickshell/UsageChip.qml quickshell/Theme.qml quickshell/Bar.qml quickshell/README.md
git commit -m "quickshell: sort the Claude chips by ccflare priority, fill the primary

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: PR → bots → merge → roll out on hexane → verify

**Files:**
- Modify (separate repo `~/docs`): `docs/systems/hexane/hyprland-bars.md` (one bullet)

- [ ] **Step 1: Push + open the PR**

```bash
git -C /home/vania/.dotfiles-worktrees/claude-pool-chips push -u origin feat/claude-pool-chips
gh pr create --repo issmirnov/dotfiles --base master --head feat/claude-pool-chips \
  --title "quickshell: sort the Claude chips by ccflare priority and fill the primary" --body-file /tmp/pr-body.md
```

PR body (written to `/tmp/pr-body.md` first): what changed, why, test evidence (blocklet suite output, QA screenshots described), and the line `🤖 Generated with [Claude Code](https://claude.com/claude-code)` at the end.

- [ ] **Step 2: Wait for the bots** — use the `watching-pr-bot-reviews` skill: `prbots wait <PR>` in the background, then `prbots <PR>`. Fix any real findings on the branch (new commit, re-run the suite), push, and wait again until the verdict is CLEAN.

- [ ] **Step 3: Merge**

```bash
gh pr merge <PR> --repo issmirnov/dotfiles --squash
git -C /home/vania/.dotfiles push origin --delete feat/claude-pool-chips
```

- [ ] **Step 4: Roll out locally**

```bash
git -C /home/vania/.dotfiles fetch origin
git -C /home/vania/.dotfiles diff --name-only HEAD origin/master   # must not list hypr/hyprland.lua
git -C /home/vania/.dotfiles merge --ff-only origin/master
pkill -x qs; hyprctl dispatch 'hl.dsp.exec_cmd("qs >/tmp/qs.log 2>&1")'
```

Check `/tmp/qs.log` as in Task 2 Step 6.

- [ ] **Step 5: Verify with hypr-cua** — `screenshot(output="DP-1")`, confirm the Claude chips are in priority order with the primary filled; click the primary chip, screenshot, confirm `primary · priority N` in the popup; click away. Repeat a plain screenshot on DP-2.

- [ ] **Step 6: KB + cleanup**

Add one bullet to `~/docs/docs/systems/hexane/hyprland-bars.md` (the pool chips: data source `ai_usage __pool`, isPrimary fill, priority order, blocked glyphs, 60s TTL), then `git -C ~/docs add docs/systems/hexane/hyprland-bars.md && git -C ~/docs commit` (that file only). Remove the worktree (`git -C /home/vania/.dotfiles worktree remove /home/vania/.dotfiles-worktrees/claude-pool-chips`), delete the local branch (`git -C /home/vania/.dotfiles branch -D feat/claude-pool-chips` after confirming the squash is on `origin/master`), and delete `/tmp/qs-pool-fixture`, `/tmp/ccflare-src.*`, `/tmp/qsbar-*.png`.
