#!/bin/bash

# Read JSON input from stdin
input=$(cat)

# Extract data from JSON
model=$(echo "$input" | jq -r '.model.display_name // "Unknown"')
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // "~"')
remaining=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty')
# Use Claude Code's pre-calculated cost (accounts for cache read/write pricing and multi-model usage)
total_cost_usd=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')

# Format cost to 2 decimal places
formatted_cost=$(printf "%.2f" "$total_cost_usd" 2>/dev/null || echo "0.00")

# Get git information if in a git repository
git_info=""
if git rev-parse --git-dir > /dev/null 2>&1; then
  branch=$(git -c core.useBuiltinFSMonitor=false rev-parse --abbrev-ref HEAD 2>/dev/null)
  if [ -n "$branch" ]; then
    # Get diff stats
    added=$(git -c core.useBuiltinFSMonitor=false diff --numstat 2>/dev/null | awk '{s+=$1} END {print s+0}')
    removed=$(git -c core.useBuiltinFSMonitor=false diff --numstat 2>/dev/null | awk '{s+=$2} END {print s+0}')
    
    git_info=" | $branch"
    if [ "$added" -gt 0 ] || [ "$removed" -gt 0 ]; then
      git_info="$git_info (+$added -$removed)"
    fi
  fi
fi

# Build context info
context_info=""
if [ -n "$remaining" ]; then
  context_info=" | Context: ${remaining}%"
fi

# Shorten working directory if needed (replace home with ~)
cwd_display="${cwd/#$HOME/~}"

# Output status line
printf "%s | %s | Cost: \$%s%s%s" "$model" "$cwd_display" "$formatted_cost" "$context_info" "$git_info"
