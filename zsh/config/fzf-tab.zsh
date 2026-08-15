# vim:ft=zsh
# fzf-tab: render zsh's native completion menu inside fzf, with previews.
# The plugin is loaded via zgen in ~/.dotfiles/zsh/zshrc (before
# zsh-autosuggestions / zsh-syntax-highlighting). This file only configures it,
# which is timing-insensitive (zstyles are read when you press TAB).
#
# Docs: https://github.com/Aloxaf/fzf-tab

# fzf-tab replaces zsh's built-in menu selection; OMZ enables `menu select`,
# which conflicts, so turn it off.
zstyle ':completion:*' menu no

# Inherit our FZF_DEFAULT_OPTS (colours/height from zsh/config/fzf.zsh) instead
# of fzf-tab's private defaults, so the picker matches the rest of our fzf UI.
zstyle ':fzf-tab:*' use-fzf-default-opts yes

# Switch between completion groups (e.g. files vs dirs) with , and .
zstyle ':fzf-tab:*' switch-group ',' '.'

# --- Previews -------------------------------------------------------------
# Directories (cd, and zoxide's z): list contents. eza/exa if present, else ls.
zstyle ':fzf-tab:complete:cd:*' fzf-preview \
  'eza -1a --icons --group-directories-first --color=always "$realpath" 2>/dev/null || exa -1a --color=always "$realpath" 2>/dev/null || ls -1A --color=always "$realpath"'
zstyle ':fzf-tab:complete:__zoxide_z:*' fzf-preview \
  'eza -1a --icons --group-directories-first --color=always "$realpath" 2>/dev/null || exa -1a --color=always "$realpath" 2>/dev/null || ls -1A --color=always "$realpath"'

# Files for common file-taking commands: bat if available, else cat.
zstyle ':fzf-tab:complete:(bat|cat|less|vim|nvim|vi|nano|cp|mv|rm|chmod|chown):*' fzf-preview \
  'bat --color=always --style=numbers --line-range=:300 "$realpath" 2>/dev/null || cat "$realpath" 2>/dev/null || ls -ld "$realpath"'

# Environment variables: show the value.
zstyle ':fzf-tab:complete:(-command-|-parameter-|-brace-parameter-|export|unset|expand):*' \
  fzf-preview 'echo ${(P)word}'

# git refs/commits: preview what they point at.
zstyle ':fzf-tab:complete:git-(checkout|switch|show|log|rebase|merge|diff):*' fzf-preview \
  'git log --oneline --color=always -20 "$word" 2>/dev/null || git show --color=always --stat "$word" 2>/dev/null'

# systemd units: show status.
zstyle ':fzf-tab:complete:systemctl-*:*' fzf-preview \
  'SYSTEMD_COLORS=1 systemctl status "$word" 2>/dev/null'
