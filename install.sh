#!/usr/bin/env bash
# Install airlock into ~/.local and link `claude` to it.
set -euo pipefail

repo_dir=$(cd -P "$(dirname "$0")" && pwd)             # this checkout
bin_dir="$HOME/.local/bin"                             # where the script goes
image_dir="$HOME/.local/share/airlock/image"           # where bin/airlock looks for the Containerfile

mkdir -p "$bin_dir" "$image_dir"
install -m 0755 "$repo_dir/bin/airlock" "$bin_dir/airlock"
install -m 0644 "$repo_dir/image/"* "$image_dir/"

# Typing `claude` is the whole point, so link it unless asked not to.
if [ "${1:-}" != "--no-link" ]; then
    ln -sf "$bin_dir/airlock" "$bin_dir/claude"
    other_claude=$(command -v claude 2>/dev/null || true)
    if [ -n "$other_claude" ] && [ "$other_claude" != "$bin_dir/claude" ]; then
        printf 'warning: %s comes first in PATH - put %s before it\n' "$other_claude" "$bin_dir" >&2
    fi
fi

case ":$PATH:" in
    *":$bin_dir:"*) ;;
    *) printf "add to ~/.zshrc: export PATH=\"%s:\$PATH\"\n" "$bin_dir" >&2 ;;
esac

printf 'done - cd into a project and type: claude\n'
