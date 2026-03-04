#!/bin/bash

# Read JSON input from stdin
input=$(cat)

# Extract data from JSON
model=$(echo "$input" | jq -r '.model.display_name // "Unknown"')
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // "~"')
remaining=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty')
total_input=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
total_output=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')

# Calculate cost based on model and token usage
# Pricing as of January 2025 (per million tokens)
case "$model" in
  *"Opus 4"*)
    input_price=15.00
    output_price=75.00
    ;;
  *"Sonnet 4"*)
    input_price=3.00
    output_price=15.00
    ;;
  *"Haiku 4"*)
    input_price=0.80
    output_price=4.00
    ;;
  *"Opus 3.5"*|*"Opus 3"*)
    input_price=15.00
    output_price=75.00
    ;;
  *"Sonnet 3.5"*|*"Sonnet 3"*)
    input_price=3.00
    output_price=15.00
    ;;
  *"Haiku 3.5"*|*"Haiku 3"*)
    input_price=0.80
    output_price=4.00
    ;;
  *)
    input_price=3.00
    output_price=15.00
    ;;
esac

# Calculate cost (tokens / 1,000,000 * price)
input_cost=$(echo "scale=4; $total_input / 1000000 * $input_price" | bc -l)
output_cost=$(echo "scale=4; $total_output / 1000000 * $output_price" | bc -l)
total_cost=$(echo "scale=4; $input_cost + $output_cost" | bc -l)

# Format cost to 2 decimal places
formatted_cost=$(printf "%.2f" "$total_cost" 2>/dev/null || echo "0.00")

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
