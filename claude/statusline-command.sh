#!/usr/bin/env bash
input=$(cat)

BOLD_GREEN='\033[1;32m'
CYAN='\033[36m'
BOLD_BLUE='\033[1;34m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
MAGENTA='\033[35m'
RESET='\033[0m'

DIR=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
HOME_DIR="$HOME"
DIR="${DIR/#$HOME_DIR/~}"
BASENAME=$(basename "$DIR")

MODEL=$(echo "$input" | jq -r '.model.display_name // ""')
SESSION_NAME=$(echo "$input" | jq -r '.session_name // ""')
VERSION=$(echo "$input" | jq -r '.version // ""')
OUTPUT_STYLE=$(echo "$input" | jq -r '.output_style.name // ""')
COST_USD=$(echo "$input" | jq -r '.cost.total_cost_usd // empty')

# Cache efficiency
CACHE_READ=$(echo "$input" | jq -r '.context_window.current_usage.cache_read_input_tokens // empty')
CACHE_CREATE=$(echo "$input" | jq -r '.context_window.current_usage.cache_creation_input_tokens // empty')

# Robbyrussell-style prompt
PROMPT_PART="${BOLD_GREEN}➜${RESET} ${CYAN}${BASENAME}${RESET}"

# Git info with dirty indicator
if [ -d "${DIR/#\~/$HOME_DIR}/.git" ] || git -C "${DIR/#\~/$HOME_DIR}" rev-parse --git-dir >/dev/null 2>&1; then
    BRANCH=$(git -C "${DIR/#\~/$HOME_DIR}" symbolic-ref --short HEAD 2>/dev/null)
    if [ -n "$BRANCH" ]; then
        DIRTY=""
        if ! git -C "${DIR/#\~/$HOME_DIR}" diff --quiet 2>/dev/null || ! git -C "${DIR/#\~/$HOME_DIR}" diff --cached --quiet 2>/dev/null; then
            DIRTY=" ${YELLOW}✗${RESET}"
        fi
        PROMPT_PART="${PROMPT_PART} ${BOLD_BLUE}git:(${RED}${BRANCH}${BOLD_BLUE})${RESET}${DIRTY}"
    fi
fi

# Worktree indicator
WORKTREE=$(echo "$input" | jq -r '.worktree.name // ""')
if [ -n "$WORKTREE" ]; then
    PROMPT_PART="${PROMPT_PART} ${YELLOW}🌿 ${WORKTREE}${RESET}"
fi

# Session name
if [ -n "$SESSION_NAME" ]; then
    PROMPT_PART="${PROMPT_PART} ${MAGENTA}[${SESSION_NAME}]${RESET}"
fi

PCT=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

# Session cost
COST_STR=""
if [ -n "$COST_USD" ]; then
    COST_STR=$(printf "${YELLOW}\$%.2f${RESET}" "$COST_USD")
fi

# Cache efficiency (percentage of reads vs total cache operations)
CACHE_STR=""
if [ -n "$CACHE_READ" ] && [ -n "$CACHE_CREATE" ]; then
    CACHE_TOTAL=$((CACHE_READ + CACHE_CREATE))
    if [ "$CACHE_TOTAL" -gt 0 ]; then
        CACHE_PCT=$((CACHE_READ * 100 / CACHE_TOTAL))
        if [ "$CACHE_PCT" -ge 70 ]; then
            CACHE_COLOR="$GREEN"
        elif [ "$CACHE_PCT" -ge 40 ]; then
            CACHE_COLOR="$YELLOW"
        else
            CACHE_COLOR="$RED"
        fi
        CACHE_STR="${CACHE_COLOR}cache ${CACHE_PCT}%${RESET}"
    fi
fi

# Output style + version tag
META_STR=""
if [ -n "$OUTPUT_STYLE" ] && [ "$OUTPUT_STYLE" != "default" ]; then
    META_STR="${CYAN}${OUTPUT_STYLE}${RESET}"
fi
if [ -n "$VERSION" ]; then
    if [ -n "$META_STR" ]; then
        META_STR="${META_STR} ${BOLD_BLUE}v${VERSION}${RESET}"
    else
        META_STR="${BOLD_BLUE}v${VERSION}${RESET}"
    fi
fi

# Session duration
DURATION_MS=$(echo "$input" | jq -r '.cost.total_duration_ms // empty')
DURATION_STR=""
if [ -n "$DURATION_MS" ]; then
    DURATION_SECS=$((DURATION_MS / 1000))
    DUR_HOURS=$((DURATION_SECS / 3600))
    DUR_MINS=$(( (DURATION_SECS % 3600) / 60 ))
    if [ "$DUR_HOURS" -gt 0 ]; then
        DURATION_STR="${DUR_HOURS}h${DUR_MINS}m"
    else
        DURATION_STR="${DUR_MINS}m"
    fi
fi

# Lines changed
LINES_ADDED=$(echo "$input" | jq -r '.cost.total_lines_added // empty')
LINES_REMOVED=$(echo "$input" | jq -r '.cost.total_lines_removed // empty')
LINES_STR=""
if [ -n "$LINES_ADDED" ] || [ -n "$LINES_REMOVED" ]; then
    ADDED="${LINES_ADDED:-0}"
    REMOVED="${LINES_REMOVED:-0}"
    if [ "$ADDED" -gt 0 ] || [ "$REMOVED" -gt 0 ]; then
        LINES_STR="${GREEN}+${ADDED}${RESET} ${RED}-${REMOVED}${RESET}"
    fi
fi

# Rate limit info (5-hour)
FIVE_H_PCT=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
FIVE_H_RESET=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')

# Rate limit info (7-day)
SEVEN_D_PCT=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
SEVEN_D_RESET=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

# Token counts
TOTAL_INPUT=$(echo "$input" | jq -r '.context_window.total_input_tokens // empty')
TOTAL_OUTPUT=$(echo "$input" | jq -r '.context_window.total_output_tokens // empty')

# Build rate limit part for a given window
build_rate_part() {
    local label=$1 pct=$2 reset_at=$3 unit=$4
    local part=""
    if [ -n "$pct" ]; then
        local pct_int
        pct_int=$(printf "%.0f" "$pct")
        local color
        if [ "$pct_int" -ge 90 ]; then
            color="$RED"
        elif [ "$pct_int" -ge 70 ]; then
            color="$YELLOW"
        else
            color="$GREEN"
        fi

        local reset_str=""
        if [ -n "$reset_at" ]; then
            local now diff
            now=$(date +%s)
            diff=$((reset_at - now))
            if [ "$diff" -gt 0 ]; then
                local days hours mins
                days=$((diff / 86400))
                hours=$(( (diff % 86400) / 3600 ))
                mins=$(( (diff % 3600) / 60 ))
                if [ "$days" -gt 0 ]; then
                    reset_str=" reset ${days}d${hours}h"
                elif [ "$hours" -gt 0 ]; then
                    reset_str=" reset ${hours}h${mins}m"
                else
                    reset_str=" reset ${mins}m"
                fi
            fi
        fi

        part="${label}${color}${pct_int}%${reset_str}${RESET}"
    fi
    echo "$part"
}

FIVE_PART=$(build_rate_part "5h:" "$FIVE_H_PCT" "$FIVE_H_RESET" "h")
SEVEN_PART=$(build_rate_part "7d:" "$SEVEN_D_PCT" "$SEVEN_D_RESET" "d")

# Tokens per minute: 5-minute rolling average
TPM_STR=""
if [ -n "$TOTAL_INPUT" ] && [ -n "$TOTAL_OUTPUT" ]; then
    TOTAL_TOKENS=$((TOTAL_INPUT + TOTAL_OUTPUT))
    STATE_FILE="/tmp/claude-statusline-global.log"
    NOW_SECS=$(date +%s)
    WINDOW=300

    echo "${NOW_SECS} ${TOTAL_TOKENS}" >> "$STATE_FILE"

    CUTOFF=$((NOW_SECS - WINDOW))
    if [ -f "$STATE_FILE" ]; then
        awk -v cutoff="$CUTOFF" '$1 >= cutoff' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"

        OLDEST_LINE=$(head -1 "$STATE_FILE")
        OLDEST_TIME=$(echo "$OLDEST_LINE" | awk '{print $1}')
        OLDEST_TOKENS=$(echo "$OLDEST_LINE" | awk '{print $2}')

        if [ -n "$OLDEST_TIME" ] && [ -n "$OLDEST_TOKENS" ]; then
            ELAPSED=$((NOW_SECS - OLDEST_TIME))
            TOKEN_DIFF=$((TOTAL_TOKENS - OLDEST_TOKENS))
            if [ "$ELAPSED" -gt 5 ] && [ "$TOKEN_DIFF" -gt 0 ]; then
                TPM=$((TOKEN_DIFF * 60 / ELAPSED))
                if [ "$TPM" -gt 0 ]; then
                    TPM_STR="${MAGENTA}${TPM}/m${RESET} "
                fi
            fi
        fi
    fi
fi

# Combine rate parts
RATE_PART=""
if [ -n "$FIVE_PART" ] && [ -n "$SEVEN_PART" ]; then
    RATE_PART="${TPM_STR}${FIVE_PART} ${SEVEN_PART}"
elif [ -n "$FIVE_PART" ]; then
    RATE_PART="${TPM_STR}${FIVE_PART}"
elif [ -n "$SEVEN_PART" ]; then
    RATE_PART="${TPM_STR}${SEVEN_PART}"
fi

# Context window progress bar
if [ -n "$PCT" ]; then
    PCT_INT=$(printf "%.0f" "$PCT")
    FILLED=$((PCT_INT / 10))
    EMPTY=$((10 - FILLED))
    printf -v FILL "%${FILLED}s"
    printf -v PAD "%${EMPTY}s"
    BAR="${FILL// /█}${PAD// /░}"

    if [ "$PCT_INT" -ge 90 ]; then
        BAR_COLOR="$RED"
    elif [ "$PCT_INT" -ge 70 ]; then
        BAR_COLOR="$YELLOW"
    else
        BAR_COLOR="$GREEN"
    fi

    RESULT=$(printf "${PROMPT_PART} | ${CYAN}%s${RESET} | ${BAR_COLOR}%s %d%%${RESET}" "$MODEL" "$BAR" "$PCT_INT")
else
    RESULT=$(printf "${PROMPT_PART} | ${CYAN}%s${RESET}" "$MODEL")
fi

# Append extra segments
[ -n "$COST_STR" ] && RESULT="${RESULT} | ${COST_STR}"
[ -n "$LINES_STR" ] && RESULT="${RESULT} | ${LINES_STR}"
[ -n "$CACHE_STR" ] && RESULT="${RESULT} | ${CACHE_STR}"
[ -n "$DURATION_STR" ] && RESULT="${RESULT} | ${CYAN}⏱ ${DURATION_STR}${RESET}"
[ -n "$RATE_PART" ] && RESULT="${RESULT} | ${RATE_PART}"
[ -n "$META_STR" ] && RESULT="${RESULT} | ${META_STR}"

printf '%b' "$RESULT"
