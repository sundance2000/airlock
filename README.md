# airlock

Run **Claude Code** in a Podman container: it sees only the current directory
and the internet — not your Mac, not your LAN. The image is a Python one
(`python:3.13-trixie`) with Claude Code installed natively — no Node, no npm
— plus git, ripgrep, fd, jq and [rtk](https://github.com/rtk-ai/rtk).

```sh
cd ~/code/my-project
claude
```

The container starts, resumes the last session in this folder, and stops again
when you close the terminal.

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
| `claude` | start here and resume the last session |
| `claude update` | rebuild the image and drop the containers still on the old one |
| `claude reset` | delete this folder's container and home |

`update` and `reset` are the only words airlock takes; `update` therefore
rebuilds the image instead of reaching Claude Code's own updater. Everything
else is passed through unchanged, `claude mcp list` and `claude --model opus`
included.

## Containers that stop with the terminal

A bare `claude` starts the container in the foreground and attaches to it, so
closing the terminal stops it. The container is kept, and the next `claude`
finds it and restarts it — with everything `sudo apt install` put in it. One
container per folder, named `airlock-<name>-<hash>`; list them with
`podman ps -a --filter name=airlock-`.

A container keeps the command it was created with, which is why arguments
replace it: `claude --model opus` builds a new container running exactly that,
and every bare `claude` afterwards restarts it with those arguments still in
place. `claude reset` gets you back to a plain one. Only one terminal at a
time per folder — a second is refused rather than attached to the first one's
tty.

Your real `~/.claude` and `~/.zshrc` are mounted into the container, so login,
settings, memory and sessions are the same inside and out — no copies, no
syncing. `~/.zshrc` goes in read-only; nothing in the container needs to write
it. What is in it that points at Homebrew or oh-my-zsh will not resolve there;
the container's own history and prompt settings sit in `/etc/zsh/zshrc`, which
zsh reads first, so yours still wins where they overlap.

Claude Code also keeps a `~/.claude.json` beside that directory — account,
machine id, onboarding state — and refuses to start without it. airlock puts
it in `~/.claude/claude.json` and links to it from each container home, so it
is shared like the rest and not recreated per folder. It is separate from your
Mac's own `~/.claude.json`, so the first start inside airlock asks the usual
first-run questions once.

Because `~/.claude` is the same for every folder, you log in **once**. Sessions
belong to the folder they were started in — Claude Code keys them by path, and
the folder is mounted at its real path — so the sessions are also there if you
run Claude Code on the Mac directly.

Resuming is decided inside the container, on every start: if this folder has a
session, the entrypoint adds `--continue`, and if it does not, it leaves it off
because `claude --continue` refuses to start without one. Pass any argument of
your own and it starts a normal session instead.

Two directories hold the rest:

```
~/.local/share/airlock/
├── image/     Containerfile, entrypoint and egress.nft, put there by install.sh
└── <hash>/    -> ~ in this folder's container: shell history, pip --user
```

`bin/airlock` reads the image definition from that one absolute path, so
`./install.sh` has to run once before the first `claude`, and again after you
change anything under `image/` in this repo — `claude update` builds from the
installed copy, not from your checkout. It also removes the containers that
are still on the old image, since a container keeps the image it was built
from.

## Security model

What it protects against: accidents and curiosity. An over-eager agent cannot
read `~/.ssh`, cannot touch your other projects, cannot reach your router, your
NAS or a service on your Mac.

What it does not protect against: a container escape. This is rootless Podman,
not a hypervisor. Do not run deliberately hostile code in it.

It also does not protect `~/.claude`. That directory is mounted read-write so
that one login and one set of settings serve every folder, which means the
container can change it — including writing a hook that your Mac would run the
next time you start Claude Code outside the container. That is the price of
sharing it; mount it read-only and Claude Code cannot log in or write a
session.

Every start — the first one and every restart — runs the image entrypoint as
root with `CAP_NET_ADMIN`, in a fresh network namespace:

```sh
nft -f /etc/airlock/egress.nft
exec setpriv --reuid=1000 --regid=1000 --keep-groups \
    --bounding-set=-net_admin,-net_raw -- "$@"
```

The rules in `image/egress.nft` reject every private range (RFC1918, CGNAT,
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
ownership. It starts its own throwaway containers with the same flags, so it
does not touch any container of yours. `shellcheck` runs in CI.

## License

MIT
