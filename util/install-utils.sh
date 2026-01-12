#!/bin/sh
# POSIX-compliant utility installer for fzf, cheat, bat, and zoxide
# Works on Alpine, FreeBSD, macOS, WSL, Linux, and Arch

set -e

# Colors for output (POSIX-compliant)
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    NC=''
fi

log_info() {
    printf "${GREEN}[INFO]${NC} %s\n" "$1"
}

log_warn() {
    printf "${YELLOW}[WARN]${NC} %s\n" "$1"
}

log_error() {
    printf "${RED}[ERROR]${NC} %s\n" "$1"
}

# Detect OS and package manager
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS="$ID"
    elif [ "$(uname)" = "Darwin" ]; then
        OS="macos"
    elif [ "$(uname)" = "FreeBSD" ]; then
        OS="freebsd"
    else
        OS="unknown"
    fi

    log_info "Detected OS: $OS"
}

# Detect package manager
detect_package_manager() {
    if command -v apk >/dev/null 2>&1; then
        PKG_MGR="apk"
    elif command -v pacman >/dev/null 2>&1; then
        PKG_MGR="pacman"
    elif command -v apt-get >/dev/null 2>&1; then
        PKG_MGR="apt"
    elif command -v dnf >/dev/null 2>&1; then
        PKG_MGR="dnf"
    elif command -v yum >/dev/null 2>&1; then
        PKG_MGR="yum"
    elif command -v brew >/dev/null 2>&1; then
        PKG_MGR="brew"
    elif command -v pkg >/dev/null 2>&1; then
        PKG_MGR="pkg"
    else
        PKG_MGR="none"
    fi

    log_info "Package manager: $PKG_MGR"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if we need sudo
use_sudo() {
    if [ "$(id -u)" -eq 0 ]; then
        echo ""
    elif command_exists sudo; then
        echo "sudo"
    else
        echo ""
    fi
}

# Install via package manager
install_via_pkg_mgr() {
    tool="$1"
    pkg_name="$2"
    SUDO="$(use_sudo)"

    case "$PKG_MGR" in
        apk)
            $SUDO apk add --no-cache "$pkg_name"
            ;;
        pacman)
            $SUDO pacman -S --noconfirm "$pkg_name"
            ;;
        apt)
            $SUDO apt-get update && $SUDO apt-get install -y "$pkg_name"
            ;;
        dnf|yum)
            $SUDO "$PKG_MGR" install -y "$pkg_name"
            ;;
        brew)
            brew install "$pkg_name"
            ;;
        pkg)
            $SUDO pkg install -y "$pkg_name"
            ;;
        *)
            return 1
            ;;
    esac
}

# Get latest release from GitHub
get_latest_release() {
    repo="$1"
    curl -s "https://api.github.com/repos/$repo/releases/latest" | \
        grep '"tag_name":' | \
        sed -E 's/.*"([^"]+)".*/\1/'
}

# Detect architecture
detect_arch() {
    arch="$(uname -m)"
    case "$arch" in
        x86_64|amd64)
            echo "x86_64"
            ;;
        aarch64|arm64)
            echo "arm64"
            ;;
        armv7l)
            echo "armv7"
            ;;
        *)
            echo "$arch"
            ;;
    esac
}

# Check if we should use package manager (only macOS and Arch)
should_use_pkg_mgr() {
    if [ "$OS" = "macos" ] || [ "$PKG_MGR" = "brew" ]; then
        return 0
    fi
    if [ "$OS" = "arch" ] || [ "$PKG_MGR" = "pacman" ]; then
        return 0
    fi
    return 1
}

# Install fzf
install_fzf() {
    if command_exists fzf; then
        log_warn "fzf is already installed"
        return 0
    fi

    log_info "Installing fzf..."

    # Use package manager only for macOS and Arch
    if should_use_pkg_mgr; then
        if install_via_pkg_mgr fzf fzf 2>/dev/null; then
            log_info "fzf installed via package manager"
            return 0
        fi
    fi

    log_info "Installing fzf from GitHub releases..."
    arch="$(detect_arch)"
    version="$(get_latest_release junegunn/fzf)"
    # Strip 'v' prefix from version for fzf URLs
    version_no_v="$(echo "$version" | sed 's/^v//')"

    case "$(uname)" in
        Linux)
            case "$arch" in
                x86_64)
                    url="https://github.com/junegunn/fzf/releases/download/${version}/fzf-${version_no_v}-linux_amd64.tar.gz"
                    ;;
                arm64)
                    url="https://github.com/junegunn/fzf/releases/download/${version}/fzf-${version_no_v}-linux_arm64.tar.gz"
                    ;;
                armv7)
                    url="https://github.com/junegunn/fzf/releases/download/${version}/fzf-${version_no_v}-linux_armv7.tar.gz"
                    ;;
                *)
                    log_error "Unsupported architecture for fzf: $arch"
                    return 1
                    ;;
            esac
            ;;
        Darwin)
            url="https://github.com/junegunn/fzf/releases/download/${version}/fzf-${version_no_v}-darwin_amd64.zip"
            ;;
        FreeBSD)
            url="https://github.com/junegunn/fzf/releases/download/${version}/fzf-${version_no_v}-freebsd_amd64.tar.gz"
            ;;
    esac

    tmpdir="$(mktemp -d)"
    cd "$tmpdir"
    curl -L "$url" -o fzf.tar.gz
    tar xzf fzf.tar.gz
    mkdir -p ~/.local/bin
    mv fzf ~/.local/bin/
    cd - >/dev/null
    rm -rf "$tmpdir"
    log_info "fzf installed to ~/.local/bin"
}

# Install bat
install_bat() {
    if command_exists bat || command_exists batcat; then
        log_warn "bat is already installed"
        return 0
    fi

    log_info "Installing bat..."

    # Use package manager only for macOS and Arch
    if should_use_pkg_mgr; then
        if install_via_pkg_mgr bat bat 2>/dev/null; then
            log_info "bat installed via package manager"
            return 0
        fi
    fi

    log_info "Installing bat from GitHub releases..."
    arch="$(detect_arch)"
    version="$(get_latest_release sharkdp/bat)"

    case "$(uname)" in
        Linux)
            case "$arch" in
                x86_64)
                    url="https://github.com/sharkdp/bat/releases/download/${version}/bat-${version}-x86_64-unknown-linux-musl.tar.gz"
                    ;;
                arm64)
                    url="https://github.com/sharkdp/bat/releases/download/${version}/bat-${version}-aarch64-unknown-linux-gnu.tar.gz"
                    ;;
                *)
                    log_error "Unsupported architecture for bat: $arch"
                    return 1
                    ;;
            esac
            ;;
        Darwin)
            url="https://github.com/sharkdp/bat/releases/download/${version}/bat-${version}-x86_64-apple-darwin.tar.gz"
            ;;
        FreeBSD)
            log_error "Please install bat manually on FreeBSD"
            return 1
            ;;
    esac

    tmpdir="$(mktemp -d)"
    cd "$tmpdir"
    curl -L "$url" -o bat.tar.gz
    tar xzf bat.tar.gz
    mkdir -p ~/.local/bin
    find . -name bat -type f -executable -exec cp {} ~/.local/bin/ \;
    cd - >/dev/null
    rm -rf "$tmpdir"
    log_info "bat installed to ~/.local/bin"
}

# Install zoxide
install_zoxide() {
    if command_exists zoxide; then
        log_warn "zoxide is already installed"
        return 0
    fi

    log_info "Installing zoxide..."

    # Use package manager only for macOS and Arch
    if should_use_pkg_mgr; then
        if install_via_pkg_mgr zoxide zoxide 2>/dev/null; then
            log_info "zoxide installed via package manager"
            return 0
        fi
    fi

    log_info "Installing zoxide from GitHub..."
    curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
    log_info "zoxide installed"
}

# Detect if system uses musl libc
is_musl() {
    if [ -f /etc/alpine-release ]; then
        return 0
    fi
    if ldd /bin/sh 2>/dev/null | grep -q musl; then
        return 0
    fi
    return 1
}

# Install cheat
install_cheat() {
    if command_exists cheat; then
        log_warn "cheat is already installed"
        return 0
    fi

    log_info "Installing cheat..."

    # Use package manager only for macOS and Arch
    if should_use_pkg_mgr; then
        if install_via_pkg_mgr cheat cheat 2>/dev/null; then
            log_info "cheat installed via package manager"
            return 0
        fi
    fi

    log_info "Installing cheat from GitHub releases..."

    # Check if musl-based system (Alpine)
    if is_musl; then
        log_info "Detected musl libc system (Alpine). Installing glibc compatibility layer..."

        # Install gcompat to run glibc binaries on Alpine
        if ! command_exists /lib/ld-linux-x86-64.so.2; then
            if ! install_via_pkg_mgr gcompat gcompat 2>/dev/null; then
                log_warn "Could not install gcompat. Cheat may not work."
            fi
        fi
    fi

    arch="$(detect_arch)"
    version="$(get_latest_release cheat/cheat)"

    case "$(uname)" in
        Linux)
            case "$arch" in
                x86_64)
                    url="https://github.com/cheat/cheat/releases/download/${version}/cheat-linux-amd64.gz"
                    ;;
                arm64)
                    url="https://github.com/cheat/cheat/releases/download/${version}/cheat-linux-arm64.gz"
                    ;;
                *)
                    log_error "Unsupported architecture for cheat: $arch"
                    return 1
                    ;;
            esac
            ;;
        Darwin)
            url="https://github.com/cheat/cheat/releases/download/${version}/cheat-darwin-amd64.gz"
            ;;
        FreeBSD)
            url="https://github.com/cheat/cheat/releases/download/${version}/cheat-freebsd-amd64.gz"
            ;;
    esac

    tmpdir="$(mktemp -d)"
    cd "$tmpdir"
    curl -L "$url" -o cheat.gz
    gunzip cheat.gz
    chmod +x cheat
    mkdir -p ~/.local/bin
    mv cheat ~/.local/bin/
    cd - >/dev/null
    rm -rf "$tmpdir"
    log_info "cheat installed to ~/.local/bin"
}

# Main installation
main() {
    log_info "Starting utility installation..."

    detect_os
    detect_package_manager

    # Check for required commands
    if ! command_exists curl; then
        log_error "curl is required but not installed. Please install curl first."
        exit 1
    fi

    # Install each utility
    install_fzf || log_error "Failed to install fzf"
    install_bat || log_error "Failed to install bat"
    install_zoxide || log_error "Failed to install zoxide"
    install_cheat || log_error "Failed to install cheat"

    log_info "Installation complete!"
    log_info "Make sure ~/.local/bin is in your PATH"
    log_info ""
    log_info "Add to your shell config:"
    log_info '  export PATH="$HOME/.local/bin:$PATH"'
}

main "$@"
