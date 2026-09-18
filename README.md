# airlock

Run **Claude Code** in a Podman container: it sees only the current directory
and the internet — not your Mac, not your LAN. The image is a Python one
(`python:3.13-bookworm`) with Claude Code installed natively — no Node, no npm.

```sh
cd ~/code/my-project
claude
```

The container starts, resumes the last session in this folder, and is gone
again the moment you close the terminal.

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
| `claude [args]` | start here; without arguments it resumes the last session |
| `claude shell` | a zsh shell in a container of its own |
| `claude update` | rebuild the image with the current Claude Code |
| `claude reset` | delete this folder's container home |

These four words are taken by airlock, so `claude update` rebuilds the image
instead of reaching Claude Code's own updater. Everything else is passed
through unchanged, `claude mcp list` and `claude --model opus` included.

## One container per run

Each invocation is a single `podman run --rm -it`. Nothing keeps running in the
background: close the terminal and the container is gone, along with anything
`sudo apt install` put in it. What survives lives in two directories on your Mac:

```
~/.local/share/airlock/
├── claude/          -> ~/.claude in every container: login, settings, sessions
└── <hash>/home/     -> ~ in this folder's container: shell history, pip --user
```

Because `~/.claude` is shared, you log in **once** and every folder is logged
in. Sessions still belong to the folder they were started in — Claude Code keys
them by path — which is why a bare `claude` continues where you left off.

On every start these are copied from your Mac into the container, with the Mac
as the source of truth:

* `~/.claude/settings.json`, `~/.claude/CLAUDE.md`, `~/.claude/commands/`, `~/.claude/agents/`
* `~/.zshrc`

Edit them on the Mac, not in the container — a copy inside is overwritten on
the next start. Anything in your `~/.zshrc` that points at Homebrew or
oh-my-zsh will not resolve inside the container; the container's own history
and prompt settings are applied before your file is read, so they survive.

## Security model

What it protects against: accidents and curiosity. An over-eager agent cannot
read `~/.ssh`, cannot touch your other projects, cannot reach your router, your
NAS or a service on your Mac.

What it does not protect against: a container escape. This is rootless Podman,
not a hypervisor. Do not run deliberately hostile code in it.

The container starts as root with `CAP_NET_ADMIN` and runs one entrypoint:

```sh
nft -f /etc/airlock/egress.nft
exec setpriv --reuid=1000 --regid=1000 --init-groups \
    --bounding-set=-net_admin,-net_raw -- "$@"
```

The rules in `share/egress.nft` reject every private range (RFC1918, CGNAT,
link-local, loopback, multicast and the IPv6 equivalents). Dropping the two
capabilities from the **bounding set** is permanent and inherited by every
later process, so `sudo` inside the container cannot get them back and cannot
touch the rules. If `nft` fails, the entrypoint exits and Claude never starts.

DNS uses `9.9.9.9` and `1.1.1.1` because your router's resolver sits in a
blocked range. IPv6 is off inside the container. Files created in the container
belong to you on the Mac (`--userns=keep-id`).

**Known gap:** if your router does port forwarding *and* hairpin NAT, those
ports are reachable from the container via your own public IP. That looks like
ordinary internet traffic and is not covered by these rules.

## Tests

`tests/acceptance.sh` checks the above against real containers: internet up,
private ranges down, `sudo nft flush ruleset` denied, mount isolation, file
ownership, nothing left running. `shellcheck` runs in CI.

## License

MIT
