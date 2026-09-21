#!/usr/bin/env bash
# Install airlock into ~/.local and link `claude` to it.
set -euo pipefail

bin="$HOME/.local/bin"                        # where the script goes
files="$HOME/.local/share/airlock/image"      # where the image definition goes
src=$(cd -P "$(dirname "$0")" && pwd)         # this repo

mkdir -p "$bin" "$files"
install -m 0755 "$src/bin/airlock" "$bin/airlock"
install -m 0644 "$src/share/"* "$files/"

# Typing `claude` is the whole point, so link it unless asked not to.
if [ "${1:-}" != "--no-link" ]; then
    ln -sf "$bin/airlock" "$bin/claude"
    native=$(command -v claude 2>/dev/null || true)
    if [ -n "$native" ] && [ "$native" != "$bin/claude" ]; then
        printf 'warning: %s comes first in PATH - put %s before it\n' "$native" "$bin" >&2
    fi
fi

case ":$PATH:" in
    *":$bin:"*) ;;
    *) printf "add to ~/.zshrc: export PATH=\"%s:\$PATH\"\n" "$bin" >&2 ;;
esac

printf 'done - cd into a project and type: claude\n'
