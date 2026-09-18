# airlock

Run **Claude Code** in a Podman container: it sees only the current directory
and the internet — not your Mac, not your LAN. The image is a Python one
(`python:3.13-bookworm`) with Claude Code installed natively — no Node, no npm.

```sh
cd ~/code/my-project
claude
```

That's it. The container for this folder is created on first use, started if
needed, and the last session in this folder is resumed automatically.

> Unofficial community tool, not affiliated with Anthropic.

## Install

Needs macOS, Podman ≥ 4.3 (`brew install podman`) and a running VM
(`podman machine init` once, then `podman machine start`).

```sh
git clone https://github.com/sundance2000/airlock.git
cd airlock && ./install.sh
```

This installs `~/.local/bin/airlock` and links `claude` to it. If you already
have a native Claude Code, `~/.local/bin` has to come first in your `PATH` —
the installer warns you if it does not. `./install.sh --no-link` skips the link.

## Commands

| | |
|---|---|
| `claude [args]` | start here, resume the last session; arguments are passed through |
| `claude :shell` | a zsh shell in the same container, alongside Claude |
| `claude :update` | update Claude Code inside the container |
| `claude :rebuild` | rebuild the image |
| `claude :reset` | delete this folder's container and home |

## Login and settings

You log in **once**. `~/.local/share/airlock/claude/` is mounted as
`~/.claude` into every container, so the login, your settings and all sessions
are shared across folders — while sessions still belong to the folder they were
started in, because Claude Code keys them by path.

On every start these are copied from your Mac into the container, with the Mac
as the source of truth:

* `~/.claude/settings.json`, `~/.claude/CLAUDE.md`, `~/.claude/commands/`, `~/.claude/agents/`
* `~/.zshrc`

Edit them on the Mac, not in the container — a copy inside gets overwritten on
the next start. Anything in your `~/.zshrc` that points at Homebrew or
oh-my-zsh will not resolve inside the container; the container's own history
and prompt settings are applied before your file is read, so they survive.

`~/.local/share/airlock/<hash>/home/` is the rest of the home, one per folder:
shell history and anything installed with `pip install --user`. Packages from
`sudo apt install` live in the container and survive stop/start, but not
`:reset`.

## Security model

What it protects against: accidents and curiosity. An over-eager agent cannot
read `~/.ssh`, cannot touch your other projects, cannot reach your router, your
NAS or a service on your Mac.

What it does not protect against: a container escape. This is rootless Podman,
not a hypervisor. Do not run deliberately hostile code in it.

The rules in `share/egress.nft` reject every private range (RFC1918, CGNAT,
link-local, loopback, multicast and the IPv6 equivalents) and are applied
inside the container's network namespace by a short-lived helper that has
`CAP_NET_ADMIN`. The container itself runs with `--cap-drop NET_ADMIN,NET_RAW`,
so nothing inside it — not even `sudo` — can change them. Applying and
verifying happens on every start; if it fails, the container is stopped and
nothing runs.

DNS uses `9.9.9.9` and `1.1.1.1` because your router's resolver sits in a
blocked range. IPv6 is off inside the container. Files created in the container
belong to you on the Mac (`--userns=keep-id`).

**Known gap:** if your router does port forwarding *and* hairpin NAT, those
ports are reachable from the container via your own public IP. That looks like
ordinary internet traffic and is not covered by these rules.

## Tests

`tests/acceptance.sh` checks the above against a real container: internet up,
private ranges down, `sudo nft flush ruleset` denied, mount isolation, file
ownership. `shellcheck` runs in CI.

## License

MIT
