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

# --- usage-capped primary: ccflare's router skips a usage_exhausted account, but its
# /api/accounts still flags it isPrimary, so the next routable account is the primary ---
cap() { jq --arg n "$1" '(.[] | select(.name==$n)) |= (.rateLimitStatus="usage_exhausted (560m)" | .usageData.seven_day.utilization=100)'; }
cp=$(cap claude-vaniaspeedy < "$F" | BLOCK_INSTANCE=claude bash "$S" __poolrender)
assert_eq "capped primary demoted"        "false"                         "$(field claude-vaniaspeedy primary "$cp")"
assert_eq "capped primary blocked"        "exhausted"                     "$(field claude-vaniaspeedy blocked "$cp")"
assert_eq "capped primary glyph"          "CC va 🪫 75/100"                "$(field claude-vaniaspeedy text "$cp")"
assert_eq "capped primary status"         "usage exhausted · priority 2"  "$(field claude-vaniaspeedy status "$cp")"
assert_eq "capped primary red"            "#FF1744"                       "$(field claude-vaniaspeedy color "$cp")"
assert_eq "next routable account is lit"  "true"                          "$(field claude-omega primary "$cp")"
assert_eq "next routable account status"  "primary · priority 20"         "$(field claude-omega status "$cp")"
assert_eq "capped primary: exactly one primary" "1"                       "$(nprimary "$cp")"
cs=$(cap claude-omega < "$F" | BLOCK_INSTANCE=claude bash "$S" __poolrender)
assert_eq "capped standby blocked"        "exhausted"                     "$(field claude-omega blocked "$cs")"
assert_eq "capped standby glyph"          "CC om 🪫 10/100"                "$(field claude-omega text "$cs")"
assert_eq "capped standby: primary kept"  "true"                          "$(field claude-vaniaspeedy primary "$cs")"
cpp=$(cap claude-smirnovlabs < "$F" | BLOCK_INSTANCE=claude bash "$S" __poolrender)
assert_eq "paused beats exhausted"        "paused"                        "$(field claude-smirnovlabs blocked "$cpp")"
none=$(cap claude-vaniaspeedy < "$F" | cap claude-omega | BLOCK_INSTANCE=claude bash "$S" __poolrender)
assert_eq "capped primary, nothing routable: nothing lit" "0"             "$(nprimary "$none")"
cst=$(cap claude-vaniaspeedy < "$F" | BLOCK_INSTANCE=claude bash "$S" __poolrender 1)
assert_eq "capped primary, stale: nothing lit" "0"                        "$(nprimary "$cst")"
ex=$(jq '(.[] | select(.name=="claude-vaniaspeedy")) |= (.rateLimitStatus="extra_usage (560m)")' "$F" \
  | BLOCK_INSTANCE=claude bash "$S" __poolrender)
assert_eq "extra_usage still routes: stays primary" "true"                "$(field claude-vaniaspeedy primary "$ex")"
assert_eq "extra_usage: not blocked"      ""                              "$(field claude-vaniaspeedy blocked "$ex")"

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
det=$(AIUSAGE_CACHE_DIR="$TMP" AIUSAGE_NO_FETCH=1 BLOCK_INSTANCE=claude:claude-vaniaspeedy bash "$S" __detail)
assert_eq "5h limit present: popup has both rows" "5h,7d" "$(jq -r '[.windows[].label] | join(",")' <<<"$det")"
touch -d '2 minutes ago' "$TMP/claude.json"     # past the 60s TTL, inside the old 180s one
old=$(AIUSAGE_CACHE_DIR="$TMP" AIUSAGE_NO_FETCH=1 BLOCK_INSTANCE=claude bash "$S" __pool)
assert_eq "expired cache: stale"     "true"  "$(field claude-vaniaspeedy stale "$old")"
assert_eq "expired cache: unlit"     "0"     "$(nprimary "$old")"
TMP2=$(mktemp -d)
assert_eq "no cache: []" "[]" "$(AIUSAGE_CACHE_DIR="$TMP2" AIUSAGE_NO_FETCH=1 BLOCK_INSTANCE=claude bash "$S" __pool)"
rm -rf "$TMP" "$TMP2"

# --- __pool fetch path, served over file:// (fetch_claude curls "$CCFLARE_BASE/api/accounts") ---
SRV=$(mktemp -d); mkdir -p "$SRV/api"; echo dummy > "$SRV/token"; TMP3=$(mktemp -d)
pool_fetch() { AIUSAGE_CACHE_DIR="$TMP3" CCFLARE_BASE="file://$SRV" CCFLARE_TOKEN_FILE="$SRV/token" BLOCK_INSTANCE=claude bash "$S" __pool; }
anthropic_cached() { jq '[.[] | select(.provider=="anthropic")] | length' "$TMP3/claude.json"; }
cp "$F" "$SRV/api/accounts"
fetched=$(pool_fetch)
assert_eq "fetched fleet: live"             "false" "$(field claude-vaniaspeedy stale "$fetched")"
assert_eq "fetched fleet: written to cache" "5"     "$(anthropic_cached)"
# a reachable ccflare with no Anthropic accounts left is an empty pool, not an outage
echo '[{"name":"lena-chatgpt","provider":"codex"}]' > "$SRV/api/accounts"
touch -d '2 minutes ago' "$TMP3/claude.json"
assert_eq "no Anthropic accounts left: empty pool" "[]" "$(pool_fetch)"
assert_eq "empty pool isn't cached"                "5"  "$(anthropic_cached)"
# Anthropic accounts without usage yet (ccflare just restarted): last good fleet, stale
echo '[{"name":"claude-vaniaspeedy","provider":"anthropic","priority":2,"isPrimary":true}]' > "$SRV/api/accounts"
nousage=$(pool_fetch)
assert_eq "no usage yet: last good fleet" "5"    "$(jq length <<<"$nousage")"
assert_eq "no usage yet: stale"           "true" "$(field claude-vaniaspeedy stale "$nousage")"
# 5h limit disabled on every account (five_hour:null, weekly only): live, cached, weekly number only
cp "$DIR/fixtures/claude_ccflare_nosession.json" "$SRV/api/accounts"
touch -d '2 minutes ago' "$TMP3/claude.json"
nosess=$(pool_fetch)
assert_eq "no 5h limit: live"              "false"    "$(field claude-vaniaspeedy stale "$nosess")"
assert_eq "no 5h limit: primary lit"       "1"        "$(nprimary "$nosess")"
assert_eq "no 5h limit: weekly only"       "CC sl 50" "$(field claude-smirnovlabs text "$nosess")"
assert_eq "no 5h limit: weekly drives worst" "50"     "$(field claude-smirnovlabs worst "$nosess")"
assert_eq "no 5h limit: written to cache"  "2"        "$(anthropic_cached)"
touch -d '2 minutes ago' "$TMP3/claude.json"
detail=$(AIUSAGE_CACHE_DIR="$TMP3" CCFLARE_BASE="file://$SRV" CCFLARE_TOKEN_FILE="$SRV/token" \
  BLOCK_INSTANCE=claude:claude-vaniaspeedy bash "$S" __detail)
assert_eq "no 5h limit: popup weekly is live" "10"   "$(jq '.windows[] | select(.label=="7d") | .pct' <<<"$detail")"
assert_eq "no 5h limit: popup has only the 7d row" "7d" "$(jq -r '[.windows[].label] | join(",")' <<<"$detail")"
rm -rf "$SRV" "$TMP3"
finish
