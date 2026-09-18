#!/usr/bin/env bash
#
# Install airlock into ~/.local (bin/ and share/).
#
#   ./install.sh                 install, ask about the `claude` symlink
#   ./install.sh --link-claude   install and create the symlink
#   ./install.sh --no-link       install without the symlink
#   PREFIX=/usr/local ./install.sh

set -euo pipefail

PREFIX="${PREFIX:-$HOME/.local}"
BIN_DIR="$PREFIX/bin"
DATA_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/airlock"
DIST_DIR="$DATA_ROOT/dist"

LINK_MODE="ask"

msg()  { printf 'install: %s\n' "$*" >&2; }
warn() { printf 'install: warning: %s\n' "$*" >&2; }
die()  { printf 'install: error: %s\n' "$*" >&2; exit 1; }

while [ "$#" -gt 0 ]; do
    case "$1" in
        --link-claude) LINK_MODE="yes" ;;
        --no-link)     LINK_MODE="no" ;;
        -h|--help)
            sed -n '3,9p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) die "unknown option: $1" ;;
    esac
    shift
done

SRC_DIR=$(cd -P "$(dirname "$0")" && pwd)
[ -f "$SRC_DIR/bin/airlock" ] || die "bin/airlock not found next to install.sh"

mkdir -p "$BIN_DIR" "$DIST_DIR"

install -m 0755 "$SRC_DIR/bin/airlock" "$BIN_DIR/airlock"
install -m 0644 "$SRC_DIR/share/Containerfile" "$DIST_DIR/Containerfile"
install -m 0644 "$SRC_DIR/share/bashrc" "$DIST_DIR/bashrc"
install -m 0644 "$SRC_DIR/share/egress.nft" "$DIST_DIR/egress.nft"
msg "installed $BIN_DIR/airlock"
msg "installed share files into $DIST_DIR"

case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) warn "$BIN_DIR is not in your PATH. Add it to ~/.zshrc:"
       warn "  export PATH=\"$BIN_DIR:\$PATH\"" ;;
esac

# --- optional `claude` symlink --------------------------------------------

native_claude=""
if command -v claude >/dev/null 2>&1; then
    native_claude=$(command -v claude)
    if [ "$native_claude" = "$BIN_DIR/claude" ]; then
        native_claude=""
    fi
fi

if [ "$LINK_MODE" = "ask" ]; then
    if [ -t 0 ]; then
        printf 'install: create symlink %s/claude -> airlock? [y/N] ' "$BIN_DIR" >&2
        read -r reply || reply=""
        case "$reply" in
            y|Y|yes|YES) LINK_MODE="yes" ;;
            *) LINK_MODE="no" ;;
        esac
    else
        LINK_MODE="no"
    fi
fi

if [ "$LINK_MODE" = "yes" ]; then
    if [ -e "$BIN_DIR/claude" ] && [ ! -L "$BIN_DIR/claude" ]; then
        die "$BIN_DIR/claude exists and is not a symlink - move it away first"
    fi
    ln -sf "$BIN_DIR/airlock" "$BIN_DIR/claude"
    msg "linked $BIN_DIR/claude -> airlock"

    if [ -n "$native_claude" ]; then
        warn "a native Claude Code is already installed at: $native_claude"
        warn "Typing 'claude' only reaches airlock if $BIN_DIR comes FIRST in PATH."
        warn "Check with: type -a claude"
        warn "The native binary stays available at its full path: $native_claude"
    fi
else
    msg "no 'claude' symlink created (run with --link-claude to add it later)"
    if [ -n "$native_claude" ]; then
        msg "note: a native claude exists at $native_claude"
    fi
fi

msg "done. Try: cd into a project and run 'airlock :doctor'"
