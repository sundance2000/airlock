#!/usr/bin/env bash
# Install airlock into ~/.local and link `claude` to it.
set -euo pipefail

BIN="$HOME/.local/bin"
DIST="${XDG_DATA_HOME:-$HOME/.local/share}/airlock/dist"
SRC=$(cd -P "$(dirname "$0")" && pwd)

mkdir -p "$BIN" "$DIST"
install -m 0755 "$SRC/bin/airlock" "$BIN/airlock"
install -m 0644 "$SRC/share/"* "$DIST/"

# Typing `claude` is the whole point, so link it unless asked not to.
if [ "${1:-}" != "--no-link" ]; then
    ln -sf "$BIN/airlock" "$BIN/claude"
    native=$(command -v claude 2>/dev/null || true)
    if [ -n "$native" ] && [ "$native" != "$BIN/claude" ]; then
        printf 'warning: %s comes first in PATH - put %s before it\n' "$native" "$BIN" >&2
    fi
fi

case ":$PATH:" in
    *":$BIN:"*) ;;
    *) printf "add to ~/.zshrc: export PATH=\"%s:\$PATH\"\n" "$BIN" >&2 ;;
esac

printf 'done - cd into a project and type: claude\n'
