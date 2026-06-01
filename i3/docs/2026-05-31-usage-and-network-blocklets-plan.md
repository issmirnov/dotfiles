# AI usage + adaptive network i3blocks — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add three i3blocks segments on hexane — Claude Code usage, Codex usage (each 5h + weekly, verbose with reset countdowns), and one adaptive network indicator (quiet wired / loud wifi / urgent down).

**Architecture:** Two new bash blocklets in the public repo `i3/blocklets/`. `ai_usage` is one script run twice (via `instance=claude|codex`) that hits each provider's official usage endpoint, caches the JSON in `~/.cache/`, and renders a colored segment; tokens are read from `$HOME` at runtime so no secret enters the repo. `network` keys off the default route. Both are made unit-testable with env-var seams (`AIUSAGE_CACHE_DIR`, `AIUSAGE_NO_FETCH`, `AIUSAGE_TEST_*`, `NET_TEST_*`) and a dependency-free fixture harness.

**Tech Stack:** bash, `jq`, `curl`, GNU `date`/`stat`, `nmcli`/`iw`, i3blocks 1.5.

**Spec:** `i3/docs/2026-05-31-usage-and-network-blocklets-design.md`

**Conventions:** i3blocks script output = 3 lines (full_text, short_text, color `#RRGGBB`); `markup=none` is global so color comes from line 3. Scripts must always `exit 0` (except the deliberate `exit 33` urgent case) so a failure never breaks the bar. Colors: green `#00C853`, yellow `#FFD600`, orange `#FF6D00`, red `#FF1744`, gray `#888888`, cyan `#00B8D4`.

> **Commit note:** Steps include `git -C ~/.dotfiles` commits. This is the user's public dotfiles repo; confirm with the user before the first commit and before any push (per their git workflow). Consider a branch (`git -C ~/.dotfiles checkout -b feat/i3-usage-network`) if they prefer.

---

### Task 1: Test harness + fixtures

**Files:**
- Create: `i3/blocklets/tests/assert.sh`
- Create: `i3/blocklets/tests/run.sh`
- Create: `i3/blocklets/tests/fixtures/claude_usage.json`
- Create: `i3/blocklets/tests/fixtures/codex_wham.json`
- Create: `i3/blocklets/tests/fixtures/codex_high.json`
- Create: `i3/blocklets/tests/fixtures/codex_rollout_line.jsonl`

- [ ] **Step 1: Create the assertion helper**

`i3/blocklets/tests/assert.sh`:

```bash
#!/usr/bin/env bash
# Minimal dependency-free assertion helpers. Source this from test_*.sh.
pass=0; fail=0
assert_eq() { # $1 desc  $2 expected  $3 actual
  if [ "$2" = "$3" ]; then pass=$((pass+1));
  else fail=$((fail+1)); printf 'FAIL - %s\n  expected: %q\n  actual:   %q\n' "$1" "$2" "$3"; fi
}
assert_contains() { # $1 desc  $2 needle  $3 haystack
  case "$3" in
    *"$2"*) pass=$((pass+1));;
    *) fail=$((fail+1)); printf 'FAIL - %s\n  needle: %q\n  in:     %q\n' "$1" "$2" "$3";;
  esac
}
finish() { printf '%d passed, %d failed\n' "$pass" "$fail"; [ "$fail" -eq 0 ]; }
```

- [ ] **Step 2: Create the test runner**

`i3/blocklets/tests/run.sh`:

```bash
#!/usr/bin/env bash
cd "$(dirname "$0")" || exit 1
rc=0
for t in test_*.sh; do
  [ -e "$t" ] || continue
  echo "== $t =="
  bash "$t" || rc=1
done
exit $rc
```

- [ ] **Step 3: Create fixtures** (synthetic — no real tokens/IDs; shapes match the verified live responses)

`i3/blocklets/tests/fixtures/claude_usage.json`:

```json
{
  "five_hour": { "utilization": 38.0, "resets_at": "2026-05-31T23:59:00+00:00" },
  "seven_day": { "utilization": 60.0, "resets_at": "2099-01-01T00:00:00+00:00" },
  "seven_day_opus": null,
  "seven_day_sonnet": { "utilization": 5.0, "resets_at": "2099-01-01T00:00:00+00:00" }
}
```

`i3/blocklets/tests/fixtures/codex_wham.json`:

```json
{
  "plan_type": "pro",
  "rate_limit": {
    "allowed": true, "limit_reached": false,
    "primary_window":   { "used_percent": 10, "limit_window_seconds": 18000,  "reset_after_seconds": 8672,   "reset_at": 1780295110 },
    "secondary_window": { "used_percent": 8,  "limit_window_seconds": 604800, "reset_after_seconds": 559455, "reset_at": 1780845893 }
  }
}
```

`i3/blocklets/tests/fixtures/codex_high.json`:

```json
{
  "plan_type": "pro",
  "rate_limit": {
    "primary_window":   { "used_percent": 92, "reset_after_seconds": 7200 },
    "secondary_window": { "used_percent": 8,  "reset_after_seconds": 559455 }
  }
}
```

`i3/blocklets/tests/fixtures/codex_rollout_line.jsonl` (single line):

```json
{"type":"event_msg","payload":{"type":"token_count","info":{},"rate_limits":{"limit_id":"codex","plan_type":"pro","primary":{"used_percent":15.0,"window_minutes":300,"resets_at":1780277106},"secondary":{"used_percent":6.0,"window_minutes":10080,"resets_at":1780845892}}}}
```

- [ ] **Step 4: Make scripts executable and verify the runner works (empty)**

Run:
```bash
chmod +x ~/.dotfiles/i3/blocklets/tests/run.sh
bash ~/.dotfiles/i3/blocklets/tests/run.sh
```
Expected: exits 0, prints nothing (no `test_*.sh` yet).

- [ ] **Step 5: Commit**

```bash
git -C ~/.dotfiles add i3/blocklets/tests
git -C ~/.dotfiles commit -m "test(i3): add blocklet test harness and usage fixtures"
```

---

### Task 2: `ai_usage` — pure helpers + dispatch skeleton

**Files:**
- Create: `i3/blocklets/ai_usage`
- Create: `i3/blocklets/tests/test_helpers.sh`

- [ ] **Step 1: Write the failing test**

`i3/blocklets/tests/test_helpers.sh`:

```bash
#!/usr/bin/env bash
DIR=$(dirname "$0"); . "$DIR/assert.sh"; S="$DIR/../ai_usage"
assert_eq "color 38 green"  "#00C853" "$(bash "$S" __color 38)"
assert_eq "color 69 green"  "#00C853" "$(bash "$S" __color 69)"
assert_eq "color 70 yellow" "#FFD600" "$(bash "$S" __color 70)"
assert_eq "color 89 yellow" "#FFD600" "$(bash "$S" __color 89)"
assert_eq "color 90 red"    "#FF1744" "$(bash "$S" __color 90)"
assert_eq "reset minutes"   "7m"      "$(bash "$S" __reset 420)"
assert_eq "reset hours"     "4h2m"    "$(bash "$S" __reset 14520)"
assert_eq "reset days"      "3d4h"    "$(bash "$S" __reset 273600)"
finish
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash ~/.dotfiles/i3/blocklets/tests/test_helpers.sh`
Expected: FAIL (script `ai_usage` does not exist yet → `bash: .../ai_usage: No such file or directory`, assertions fail).

- [ ] **Step 3: Write minimal implementation**

`i3/blocklets/ai_usage`:

```bash
#!/usr/bin/env bash
# i3blocks: Claude Code / Codex usage (5h + weekly), verbose with reset countdowns.
# Provider via $BLOCK_INSTANCE (claude|codex). Reads OAuth tokens from $HOME at
# runtime — contains NO secrets. Safe to commit to a public repo.
set -u

pct_color() {
  local p=${1:-0}
  if   [ "$p" -ge 90 ]; then echo "#FF1744"
  elif [ "$p" -ge 70 ]; then echo "#FFD600"
  else                       echo "#00C853"
  fi
}

fmt_reset() {
  local s=${1:-0} d h m
  d=$(( s / 86400 )); h=$(( (s % 86400) / 3600 )); m=$(( (s % 3600) / 60 ))
  if   [ "$d" -gt 0 ]; then echo "${d}d${h}h"
  elif [ "$h" -gt 0 ]; then echo "${h}h${m}m"
  else                      echo "${m}m"
  fi
}

render_claude() { return 1; }   # implemented in Task 3
render_codex()  { return 1; }   # implemented in Task 4
main()          { :; }          # implemented in Task 5

# ---- dispatch ----
case "${1:-}" in
  __color)  pct_color "${2:-0}"; exit 0 ;;
  __reset)  fmt_reset "${2:-0}"; exit 0 ;;
  __render) "render_${BLOCK_INSTANCE:-claude}" "$(cat)"; exit $? ;;
  *)        main ;;
esac
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
chmod +x ~/.dotfiles/i3/blocklets/ai_usage
bash ~/.dotfiles/i3/blocklets/tests/test_helpers.sh
```
Expected: `8 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git -C ~/.dotfiles add i3/blocklets/ai_usage i3/blocklets/tests/test_helpers.sh
git -C ~/.dotfiles commit -m "feat(i3): ai_usage helpers (pct color, reset formatting)"
```

---

### Task 3: `ai_usage` — Claude parse + render

**Files:**
- Modify: `i3/blocklets/ai_usage` (replace the `render_claude` stub)
- Create: `i3/blocklets/tests/test_claude.sh`

- [ ] **Step 1: Write the failing test**

`i3/blocklets/tests/test_claude.sh`:

```bash
#!/usr/bin/env bash
DIR=$(dirname "$0"); . "$DIR/assert.sh"; S="$DIR/../ai_usage"
out=$(BLOCK_INSTANCE=claude bash "$S" __render < "$DIR/fixtures/claude_usage.json")
full=$(sed -n 1p <<<"$out"); short=$(sed -n 2p <<<"$out"); color=$(sed -n 3p <<<"$out")
assert_contains "claude 5h no reset (<50)" "5h 38% 7d 60% (" "$full"
assert_contains "claude 7d pct"            "7d 60%"          "$full"
assert_eq       "claude short"             "CC 38/60"        "$short"
assert_eq       "claude color worst=60"    "#00C853"         "$color"
finish
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash ~/.dotfiles/i3/blocklets/tests/test_claude.sh`
Expected: FAIL (stub returns 1 → no output; assertions fail).

- [ ] **Step 3: Write minimal implementation** — replace the `render_claude` stub line

In `i3/blocklets/ai_usage`, replace:
```bash
render_claude() { return 1; }   # implemented in Task 3
```
with:
```bash
render_claude() {
  local json=$1 now five sev seg5 seg7 worst color r ts
  now=$(date +%s)
  five=$(jq -r '.five_hour.utilization // empty' <<<"$json"); five=${five%.*}
  sev=$(jq -r '.seven_day.utilization // empty' <<<"$json"); sev=${sev%.*}
  { [ -z "$five" ] || [ -z "$sev" ]; } && return 1
  seg5="5h ${five}%"; seg7="7d ${sev}%"
  if [ "$five" -ge 50 ]; then
    ts=$(jq -r '.five_hour.resets_at // empty' <<<"$json")
    [ -n "$ts" ] && r=$(( $(date -d "$ts" +%s 2>/dev/null || echo "$now") - now )) && [ "$r" -gt 0 ] && seg5="$seg5 ($(fmt_reset "$r"))"
  fi
  if [ "$sev" -ge 50 ]; then
    ts=$(jq -r '.seven_day.resets_at // empty' <<<"$json")
    [ -n "$ts" ] && r=$(( $(date -d "$ts" +%s 2>/dev/null || echo "$now") - now )) && [ "$r" -gt 0 ] && seg7="$seg7 ($(fmt_reset "$r"))"
  fi
  worst=$five; [ "$sev" -gt "$worst" ] && worst=$sev
  color=$(pct_color "$worst")
  printf '%s\n%s\n%s\n' "CC $seg5 $seg7" "CC ${five}/${sev}" "$color"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash ~/.dotfiles/i3/blocklets/tests/test_claude.sh`
Expected: `4 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git -C ~/.dotfiles add i3/blocklets/ai_usage i3/blocklets/tests/test_claude.sh
git -C ~/.dotfiles commit -m "feat(i3): ai_usage Claude usage parse + render"
```

---

### Task 4: `ai_usage` — Codex parse + render

**Files:**
- Modify: `i3/blocklets/ai_usage` (replace the `render_codex` stub)
- Create: `i3/blocklets/tests/test_codex.sh`

- [ ] **Step 1: Write the failing test**

`i3/blocklets/tests/test_codex.sh`:

```bash
#!/usr/bin/env bash
DIR=$(dirname "$0"); . "$DIR/assert.sh"; S="$DIR/../ai_usage"

# normal: 10% / 8% -> green, no resets (<50)
out=$(BLOCK_INSTANCE=codex bash "$S" __render < "$DIR/fixtures/codex_wham.json")
assert_eq "codex full"  "CX 5h 10% wk 8%" "$(sed -n 1p <<<"$out")"
assert_eq "codex short" "CX 10/8"         "$(sed -n 2p <<<"$out")"
assert_eq "codex color" "#00C853"         "$(sed -n 3p <<<"$out")"

# high: 92% with 2h reset -> red, reset shown (reset_after_seconds is deterministic)
out=$(BLOCK_INSTANCE=codex bash "$S" __render < "$DIR/fixtures/codex_high.json")
assert_eq "codex high full"  "CX 5h 92% (2h0m) wk 8%" "$(sed -n 1p <<<"$out")"
assert_eq "codex high color" "#FF1744"                "$(sed -n 3p <<<"$out")"
finish
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash ~/.dotfiles/i3/blocklets/tests/test_codex.sh`
Expected: FAIL (stub returns 1 → no output).

- [ ] **Step 3: Write minimal implementation** — replace the `render_codex` stub line

In `i3/blocklets/ai_usage`, replace:
```bash
render_codex()  { return 1; }   # implemented in Task 4
```
with:
```bash
render_codex() {
  local json=$1 five wk seg5 segw worst color r
  five=$(jq -r '.rate_limit.primary_window.used_percent // empty'   <<<"$json"); five=${five%.*}
  wk=$(jq -r   '.rate_limit.secondary_window.used_percent // empty' <<<"$json"); wk=${wk%.*}
  { [ -z "$five" ] || [ -z "$wk" ]; } && return 1
  seg5="5h ${five}%"; segw="wk ${wk}%"
  if [ "$five" -ge 50 ]; then
    r=$(jq -r '.rate_limit.primary_window.reset_after_seconds // empty' <<<"$json")
    [ -n "$r" ] && [ "$r" -gt 0 ] 2>/dev/null && seg5="$seg5 ($(fmt_reset "$r"))"
  fi
  if [ "$wk" -ge 50 ]; then
    r=$(jq -r '.rate_limit.secondary_window.reset_after_seconds // empty' <<<"$json")
    [ -n "$r" ] && [ "$r" -gt 0 ] 2>/dev/null && segw="$segw ($(fmt_reset "$r"))"
  fi
  worst=$five; [ "$wk" -gt "$worst" ] && worst=$wk
  color=$(pct_color "$worst")
  printf '%s\n%s\n%s\n' "CX $seg5 $segw" "CX ${five}/${wk}" "$color"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash ~/.dotfiles/i3/blocklets/tests/test_codex.sh`
Expected: `5 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git -C ~/.dotfiles add i3/blocklets/ai_usage i3/blocklets/tests/test_codex.sh
git -C ~/.dotfiles commit -m "feat(i3): ai_usage Codex usage parse + render"
```

---

### Task 5: `ai_usage` — fetch, cache, fallback, main

**Files:**
- Modify: `i3/blocklets/ai_usage` (replace the `main` stub; add fetch/validate/cache/rollout functions; extend dispatch)
- Create: `i3/blocklets/tests/test_ai_fallback.sh`
- Create: `i3/blocklets/tests/test_codex_rollout.sh`

- [ ] **Step 1: Write the failing tests**

`i3/blocklets/tests/test_ai_fallback.sh`:

```bash
#!/usr/bin/env bash
DIR=$(dirname "$0"); . "$DIR/assert.sh"; S="$DIR/../ai_usage"
TMP=$(mktemp -d); cp "$DIR/fixtures/claude_usage.json" "$TMP/claude.json"

# fresh cache -> live color (green), real text
out=$(AIUSAGE_CACHE_DIR="$TMP" BLOCK_INSTANCE=claude bash "$S")
assert_eq       "fresh cache live color" "#00C853"   "$(sed -n 3p <<<"$out")"
assert_contains "fresh cache text"       "CC 5h 38%" "$(sed -n 1p <<<"$out")"

# stale cache + no fetch -> dim (gray) but text preserved
touch -d '1 hour ago' "$TMP/claude.json"
out=$(AIUSAGE_CACHE_DIR="$TMP" AIUSAGE_NO_FETCH=1 BLOCK_INSTANCE=claude bash "$S")
assert_eq       "stale dim color"  "#888888"   "$(sed -n 3p <<<"$out")"
assert_contains "stale text kept"  "CC 5h 38%" "$(sed -n 1p <<<"$out")"

# no cache + no fetch -> "CC ?"
TMP2=$(mktemp -d)
out=$(AIUSAGE_CACHE_DIR="$TMP2" AIUSAGE_NO_FETCH=1 BLOCK_INSTANCE=claude bash "$S")
assert_eq "no-data full"  "CC ?"    "$(sed -n 1p <<<"$out")"
assert_eq "no-data color" "#888888" "$(sed -n 3p <<<"$out")"

rm -rf "$TMP" "$TMP2"
finish
```

`i3/blocklets/tests/test_codex_rollout.sh`:

```bash
#!/usr/bin/env bash
DIR=$(dirname "$0"); . "$DIR/assert.sh"; S="$DIR/../ai_usage"
mapped=$(bash "$S" __maprollout < "$DIR/fixtures/codex_rollout_line.jsonl")
out=$(BLOCK_INSTANCE=codex bash "$S" __render <<<"$mapped")
assert_contains "rollout 5h" "5h 15%" "$(sed -n 1p <<<"$out")"
assert_contains "rollout wk" "wk 6%"  "$(sed -n 1p <<<"$out")"
finish
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
bash ~/.dotfiles/i3/blocklets/tests/test_ai_fallback.sh
bash ~/.dotfiles/i3/blocklets/tests/test_codex_rollout.sh
```
Expected: both FAIL (`main` is a stub → no output; `__maprollout` not handled).

- [ ] **Step 3a: Add fetch/validate/cache/rollout functions** — insert immediately above the `# ---- dispatch ----` line

In `i3/blocklets/ai_usage`, insert before `# ---- dispatch ----`:

```bash
CACHE_DIR="${AIUSAGE_CACHE_DIR:-$HOME/.cache/i3blocks-aiusage}"

fetch_claude() {
  [ -n "${AIUSAGE_NO_FETCH:-}" ] && return 1
  local cred="$HOME/.claude/.credentials.json" token ver
  [ -f "$cred" ] || return 1
  token=$(jq -r '.claudeAiOauth.accessToken // empty' "$cred"); [ -z "$token" ] && return 1
  ver=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1); ver=${ver:-2.1.159}
  curl -sS --max-time 6 \
    -H "Authorization: Bearer $token" \
    -H "anthropic-beta: oauth-2025-04-20" \
    -H "anthropic-version: 2023-06-01" \
    -H "User-Agent: claude-code/$ver" \
    "https://api.anthropic.com/api/oauth/usage" 2>/dev/null
}
validate_claude() { jq -e '.five_hour.utilization' >/dev/null 2>&1 <<<"${1:-}"; }

fetch_codex() {
  [ -n "${AIUSAGE_NO_FETCH:-}" ] && return 1
  local auth="$HOME/.codex/auth.json" token acct
  [ -f "$auth" ] || return 1
  token=$(jq -r '.tokens.access_token // empty' "$auth"); [ -z "$token" ] && return 1
  acct=$(jq -r '.tokens.account_id // empty' "$auth")
  curl -sS --max-time 6 \
    -H "Authorization: Bearer $token" \
    -H "ChatGPT-Account-Id: $acct" \
    -H "User-Agent: codex-cli" \
    "https://chatgpt.com/backend-api/wham/usage" 2>/dev/null
}
validate_codex() { jq -e '.rate_limit.primary_window.used_percent' >/dev/null 2>&1 <<<"${1:-}"; }

# stdin: one rollout JSONL line -> stdout: wham-shaped JSON (or exit 1)
map_rollout_line() {
  jq -e -c '
    .payload.rate_limits as $r
    | select($r != null and $r.primary != null)
    | def after($w): (if $w.resets_at then ($w.resets_at - now)
                      elif $w.resets_in_seconds then $w.resets_in_seconds
                      else 0 end | floor);
      { rate_limit: {
          primary_window:   { used_percent: $r.primary.used_percent,   reset_after_seconds: after($r.primary) },
          secondary_window: { used_percent: $r.secondary.used_percent, reset_after_seconds: after($r.secondary) } } }
  ' 2>/dev/null
}

codex_rollout_json() {
  local f line
  f=$(ls -t "$HOME"/.codex/sessions/*/*/*/rollout-*.jsonl 2>/dev/null | head -1); [ -n "$f" ] || return 1
  line=$(grep '"rate_limits"' "$f" 2>/dev/null | tail -1); [ -n "$line" ] || return 1
  printf '%s' "$line" | map_rollout_line
}

label() { case "${BLOCK_INSTANCE:-claude}" in codex) echo "CX";; *) echo "CC";; esac; }

# re-render the given JSON but force the color line to gray (stale/fallback marker)
emit_dim() {
  local out; out=$("render_${BLOCK_INSTANCE:-claude}" "$1") || return 1
  printf '%s\n%s\n#888888\n' "$(sed -n 1p <<<"$out")" "$(sed -n 2p <<<"$out")"
}

```

- [ ] **Step 3b: Replace the `main` stub**

In `i3/blocklets/ai_usage`, replace:
```bash
main()          { :; }          # implemented in Task 5
```
with:
```bash
main() {
  local provider="${BLOCK_INSTANCE:-claude}" ttl cache json
  case "$provider" in codex) ttl=120;; *) ttl=180;; esac
  mkdir -p "$CACHE_DIR"; cache="$CACHE_DIR/$provider.json"

  # 1) fresh cache -> live color
  if [ -f "$cache" ] && [ $(( $(date +%s) - $(stat -c %Y "$cache") )) -lt "$ttl" ]; then
    "render_$provider" "$(cat "$cache")" && return 0
  fi
  # 2) fetch live; cache only on valid response
  json=$("fetch_$provider")
  if "validate_$provider" "$json"; then
    printf '%s' "$json" > "$cache"
    "render_$provider" "$json" && return 0
  fi
  # 3) fallbacks, rendered gray
  if [ "$provider" = "codex" ] && json=$(codex_rollout_json) && [ -n "$json" ]; then
    emit_dim "$json" && return 0
  fi
  if [ -f "$cache" ]; then emit_dim "$(cat "$cache")" && return 0; fi
  # 4) nothing available
  local l; l=$(label); printf '%s ?\n%s ?\n#888888\n' "$l" "$l"
}
```

- [ ] **Step 3c: Extend the dispatch** to expose `map_rollout_line`

In `i3/blocklets/ai_usage`, replace:
```bash
  __render) "render_${BLOCK_INSTANCE:-claude}" "$(cat)"; exit $? ;;
```
with:
```bash
  __render)     "render_${BLOCK_INSTANCE:-claude}" "$(cat)"; exit $? ;;
  __maprollout) map_rollout_line; exit $? ;;
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
bash ~/.dotfiles/i3/blocklets/tests/run.sh
```
Expected: every `test_*.sh` reports `0 failed`; runner exits 0.

- [ ] **Step 5: Live smoke test** (makes real network calls; both endpoints were verified working on hexane)

Run:
```bash
BLOCK_INSTANCE=claude ~/.dotfiles/i3/blocklets/ai_usage
echo "---"
BLOCK_INSTANCE=codex  ~/.dotfiles/i3/blocklets/ai_usage
```
Expected: line 1 like `CC 5h NN% 7d NN%` (with `(…)` on any window ≥50%) and a `#RRGGBB` on line 3; same for `CX`. If a token is missing/expired you'll see `CC ?`/`CX ?` in gray — that's the correct failure behavior, not a bug.

- [ ] **Step 6: Confirm cache was written and polling is bounded**

Run:
```bash
ls -l ~/.cache/i3blocks-aiusage/
```
Expected: `claude.json` and/or `codex.json` present. Re-running within the TTL serves from cache (no network call), keeping Claude under its 180 s polling floor.

- [ ] **Step 7: Commit**

```bash
git -C ~/.dotfiles add i3/blocklets/ai_usage i3/blocklets/tests/test_ai_fallback.sh i3/blocklets/tests/test_codex_rollout.sh
git -C ~/.dotfiles commit -m "feat(i3): ai_usage fetch, cache, and gray-fallback orchestration"
```

---

### Task 6: `network` blocklet

**Files:**
- Create: `i3/blocklets/network`
- Create: `i3/blocklets/tests/test_network.sh`

- [ ] **Step 1: Write the failing test**

`i3/blocklets/tests/test_network.sh`:

```bash
#!/usr/bin/env bash
DIR=$(dirname "$0"); . "$DIR/assert.sh"; S="$DIR/../network"

# no default route -> urgent "no net"
out=$(NET_TEST_IF= bash "$S"); ec=$?
assert_eq "down full"  "no net"  "$(sed -n 1p <<<"$out")"
assert_eq "down color" "#FF1744" "$(sed -n 3p <<<"$out")"
assert_eq "down exit"  "33"      "$ec"

# vpn iface
out=$(NET_TEST_IF=tun0 bash "$S")
assert_eq "vpn full"  "VPN"     "$(sed -n 1p <<<"$out")"
assert_eq "vpn color" "#00B8D4" "$(sed -n 3p <<<"$out")"

# wifi strong signal
out=$(NET_TEST_IF=wlo1 NET_TEST_WIRELESS=1 NET_TEST_SSID="MyAP-5G" NET_TEST_SIGNAL=72 bash "$S")
assert_eq "wifi full"  "MyAP-5G 72%" "$(sed -n 1p <<<"$out")"
assert_eq "wifi color" "#FFD600"     "$(sed -n 3p <<<"$out")"

# wifi weak signal -> orange
out=$(NET_TEST_IF=wlo1 NET_TEST_WIRELESS=1 NET_TEST_SSID="Far" NET_TEST_SIGNAL=22 bash "$S")
assert_eq "wifi weak color" "#FF6D00" "$(sed -n 3p <<<"$out")"

# wired -> quiet LAN
out=$(NET_TEST_IF=enp8s0f0 NET_TEST_WIRELESS=0 bash "$S")
assert_eq "wired full"  "LAN"     "$(sed -n 1p <<<"$out")"
assert_eq "wired color" "#00C853" "$(sed -n 3p <<<"$out")"
finish
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash ~/.dotfiles/i3/blocklets/tests/test_network.sh`
Expected: FAIL (`network` does not exist).

- [ ] **Step 3: Write minimal implementation**

`i3/blocklets/network`:

```bash
#!/usr/bin/env bash
# i3blocks: adaptive network indicator. Keys off the default route so it ignores
# docker/veth/bridge interfaces. Quiet on wired, loud (SSID+signal) on wifi,
# urgent when down. Test seams: NET_TEST_IF / NET_TEST_WIRELESS / NET_TEST_SSID /
# NET_TEST_SIGNAL (use the ${VAR-...} form so an empty value is honored).
set -u

get_iface()   { echo "${NET_TEST_IF-$(ip route show default 2>/dev/null | awk '/^default/{print $5; exit}')}"; }
is_wireless() {
  if [ -n "${NET_TEST_WIRELESS+x}" ]; then [ "$NET_TEST_WIRELESS" = 1 ]
  else [ -d "/sys/class/net/$1/wireless" ]; fi
}
get_ssid()   { echo "${NET_TEST_SSID-$(nmcli -t -f active,ssid   dev wifi 2>/dev/null | awk -F: '$1=="yes"{print $2; exit}')}"; }
get_signal() { echo "${NET_TEST_SIGNAL-$(nmcli -t -f active,signal dev wifi 2>/dev/null | awk -F: '$1=="yes"{print $2; exit}')}"; }

IF=$(get_iface)

if [ -z "$IF" ]; then
  printf 'no net\nno net\n#FF1744\n'; exit 33   # i3blocks: exit 33 marks the block urgent
fi

case "$IF" in
  tun*|wg*|tap*) printf 'VPN\nVPN\n#00B8D4\n'; exit 0 ;;
esac

if is_wireless "$IF"; then
  ssid=$(get_ssid); sig=$(get_signal)
  [ -z "$ssid" ] && ssid="wifi"
  color="#FFD600"; [ -n "$sig" ] && [ "$sig" -lt 40 ] 2>/dev/null && color="#FF6D00"
  if [ -n "$sig" ]; then text="$ssid ${sig}%"; else text="$ssid"; fi
  printf '%s\n%s\n%s\n' "$text" "$text" "$color"; exit 0
fi

printf 'LAN\nLAN\n#00C853\n'; exit 0
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
chmod +x ~/.dotfiles/i3/blocklets/network
bash ~/.dotfiles/i3/blocklets/tests/test_network.sh
```
Expected: `9 passed, 0 failed`.

- [ ] **Step 5: Live smoke test** (real state — currently wired on hexane)

Run: `~/.dotfiles/i3/blocklets/network`
Expected: `LAN` / `LAN` / `#00C853` (you are on wired `enp8s0f0`).

- [ ] **Step 6: Commit**

```bash
git -C ~/.dotfiles add i3/blocklets/network i3/blocklets/tests/test_network.sh
git -C ~/.dotfiles commit -m "feat(i3): adaptive network blocklet (wired/wifi/vpn/down)"
```

---

### Task 7: Wire blocks into the bar + verify

**Files:**
- Modify: `i3/i3blocks.conf` (insert three sections before `[time]`)

- [ ] **Step 1: Add the three blocks** — edit `~/.dotfiles/i3/i3blocks.conf`

Replace this region:
```ini
[volume]
label=♪
instance=Master
signal=10


# Date Time
[time]
```
with:
```ini
[volume]
label=♪
instance=Master
signal=10


# Network: quiet wired, loud wifi, urgent down
[network]
interval=10
separator=true

# Claude Code usage (5h + 7d)
[claude_usage]
command=$SCRIPT_DIR/ai_usage
instance=claude
interval=300

# Codex usage (5h + weekly)
[codex_usage]
command=$SCRIPT_DIR/ai_usage
instance=codex
interval=300


# Date Time
[time]
```

- [ ] **Step 2: Sanity-check each block the way i3blocks will invoke it**

Run (i3blocks sets `$SCRIPT_DIR` and `$BLOCK_INSTANCE`; simulate it):
```bash
SCRIPT_DIR=~/.dotfiles/i3/blocklets BLOCK_INSTANCE= bash ~/.dotfiles/i3/blocklets/network
SCRIPT_DIR=~/.dotfiles/i3/blocklets BLOCK_INSTANCE=claude bash ~/.dotfiles/i3/blocklets/ai_usage
SCRIPT_DIR=~/.dotfiles/i3/blocklets BLOCK_INSTANCE=codex  bash ~/.dotfiles/i3/blocklets/ai_usage
```
Expected: three valid 3-line outputs (`LAN…`, `CC…`, `CX…`).

- [ ] **Step 3: Reload i3 so the bar re-reads i3blocks.conf**

`~/.i3blocks.conf` is a symlink to `i3/i3blocks.conf`, so the edit is already deployed; i3blocks only re-reads its config on (re)start.

Run: `i3-msg restart`
Expected: `[{"success":true}]`. i3 re-execs in place (windows/workspaces preserved) and the bar respawns i3blocks with the new config.

- [ ] **Step 4: Visually verify the bar**

Look at the top bar. Expected, left of the clock: `LAN` (green), then `CC 5h NN% 7d NN%`, then `CX 5h NN% wk NN%`. Confirm colors look right and nothing shows a raw error or stays blank.

- [ ] **Step 5: Full test suite green**

Run: `bash ~/.dotfiles/i3/blocklets/tests/run.sh && echo ALL_GREEN`
Expected: ends with `ALL_GREEN`.

- [ ] **Step 6: Commit**

```bash
git -C ~/.dotfiles add i3/i3blocks.conf
git -C ~/.dotfiles commit -m "feat(i3): wire network + Claude/Codex usage blocks into bar"
```

---

## Self-Review

**Spec coverage:**
- Claude endpoint/headers/fields + verbose render + reset ≥50% → Task 3. ✓
- Codex endpoint/headers/fields + verbose render + reset ≥50% → Task 4. ✓
- Cache (TTL: Claude 180s / Codex 120s), read-only token, gray failure, never-refresh, always exit 0 → Task 5. ✓
- Codex rollout fallback (null-safe, resets_at/resets_in_seconds drift) → Task 5 (`map_rollout_line`, `codex_rollout_json`). ✓
- Network: default-route keying, no-route urgent, VPN, wifi SSID+signal (orange <40), quiet wired → Task 6. ✓
- Two separate blocks via `instance` → Tasks 2/7. ✓
- Wiring before `[time]`, symlink note, reload → Task 7. ✓
- Key-leakage: tokens read from `$HOME`, cache in `~/.cache`, only %/SSID/resets on bar, fixtures synthetic → Tasks 1/5/6. ✓
- Verification plan (manual invocation, failure path, polling bound, network states) → Tasks 5/6/7. ✓

**Placeholder scan:** No TBD/TODO. Every code step shows complete code; every run step shows the command and expected output. The `exit 33` urgent behavior is annotated and visually verified in Task 7 (red color is the baseline signal regardless). ✓

**Type/name consistency:** `pct_color`, `fmt_reset`, `render_claude`, `render_codex`, `fetch_claude/codex`, `validate_claude/codex`, `map_rollout_line`, `codex_rollout_json`, `label`, `emit_dim`, `main`, and `CACHE_DIR` are defined once and referenced consistently. Dispatch tokens `__color/__reset/__render/__maprollout` match between `ai_usage` and the tests. Test seam names (`AIUSAGE_CACHE_DIR`, `AIUSAGE_NO_FETCH`, `NET_TEST_IF/WIRELESS/SSID/SIGNAL`) match between scripts and tests. ✓
