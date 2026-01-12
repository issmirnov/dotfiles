# Utility Installer

A minimal, POSIX-compliant shell script to install essential CLI utilities across different platforms.

## Supported Platforms

- **Linux**: Alpine, Arch, Ubuntu/Debian, Fedora/RHEL, etc.
- **macOS**: via Homebrew or direct downloads
- **FreeBSD**: via pkg or direct downloads
- **WSL**: any Linux distribution

## Installed Utilities

- **fzf**: Command-line fuzzy finder
- **bat**: Cat clone with syntax highlighting
- **zoxide**: Smarter cd command
- **cheat**: Interactive cheatsheets

## Usage

```sh
./util/install-utils.sh
```

The script will:
1. Detect your OS and package manager
2. Attempt to install via package manager (fastest)
3. Fall back to downloading from GitHub releases if needed
4. Install binaries to `~/.local/bin` or `~/.fzf/bin`

## Requirements

- `curl` (for downloading from GitHub)
- `sudo` access (for package manager installations)
- Internet connection

## Post-Installation

Make sure these directories are in your PATH:

```sh
export PATH="$HOME/.local/bin:$HOME/.fzf/bin:$PATH"
```

Add this to your shell config (`~/.zshrc`, `~/.bashrc`, etc.)
