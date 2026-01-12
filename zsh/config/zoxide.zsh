#!/usr/bin/env zsh
##############################################################################
# zoxide - smarter cd command (replaces z plugin)
# https://github.com/ajeetdsouza/zoxide
#
# Usage:
#   z <directory>  - jump to directory
#   zi <directory> - interactive fuzzy search with fzf
#
# Install:
#   sudo pacman -S zoxide          # Arch Linux
#   cargo install zoxide --locked  # Via Rust
##############################################################################

if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init zsh)"
else
  echo "Warning: zoxide not installed. Install with: sudo pacman -S zoxide" >&2
  echo "         The 'z' command will not be available." >&2
fi
