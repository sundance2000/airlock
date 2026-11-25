# airlock

Run **Claude Code** in a Podman container: it sees only the current directory
and the internet — not your Mac, not your LAN. The image is a Python one
(`python:3.13-trixie`) with Claude Code installed natively — no Node, no npm
— plus git, ripgrep, fd, jq, oh-my-posh,
[rtk](https://github.com/rtk-ai/rtk) and
[herdr](https://github.com/ogulcancelik/herdr).

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

This installs `~/.local/bin/airlock` and links `claude` and `herdr` to it. If
you already have a native Claude Code or herdr, `~/.local/bin` has to come
first in your `PATH` — the installer warns you if it does not.
`./install.sh --no-link` skips the links.

## Commands

| | |
|---|---|
| `claude` | start here and resume the last session |
| `herdr` | start herdr here, in a container of its own |
| `claude update` | rebuild the image to pick up new tool versions |
| `claude reset` | delete this folder's containers and home |
| `airlock add port 3000` | publish a port, see [Ports](#ports) |
| `airlock remove port 3000` | and take it back |

`herdr update` and `herdr reset` do the same as their `claude` counterparts.

`update` and `reset` are the only words airlock takes; `update` therefore
rebuilds the image instead of reaching Claude Code's own updater. Everything
else is passed through unchanged, `claude mcp list` and `claude --model opus`
included. `add port` and `remove port` only work as `airlock`, so that
`claude add a login button` still reaches Claude Code.

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
change anything under `image/` in this repo. The next `claude` then notices
that the definition is newer than the image and rebuilds by itself — no
`claude update` needed for that. `claude update` is for the other direction:
rebuilding although nothing here changed, to pull in new versions of Claude
Code, rtk and oh-my-posh.

Either way the rebuild also removes the containers that are still on the old
image, because a container keeps the image it was built from. A container also
keeps the flags it was created with — mounts, capabilities, `COLORTERM` — so an
airlock newer than the container replaces it instead of restarting it.

## herdr

`herdr` in a project folder starts [herdr](https://github.com/ogulcancelik/herdr)
in a second container, `airlock-herdr-<name>-<hash>`, with the same rules,
mounts and home as the Claude Code one. Its panes open the container's zsh, so
`claude` typed in a pane is the Claude Code inside the container — no nested
containers, no Podman inside. Both containers can run side by side in the same
folder.

herdr normally keeps its server running after the client detaches. In airlock
the client is the container's main process, so detaching or closing the
terminal stops the container and the server with it, like `claude` does.

Its state — sockets, logs, `session.json` — lives in `~/.config/herdr`, and
that directory is a Podman volume, `airlock-herdr-<hash>`, not part of the
container home on your Mac: herdr's client and server talk through unix
sockets, and a socket on a directory shared from the Mac can be created but
not connected to. The volume lives in the Podman VM and survives a new
container, so the next `herdr` restores the workspace and, with the Claude
integration, the agents in it. `herdr reset` deletes it with the rest.

Your Mac's `~/.config/herdr/config.toml`, if there is one, is mounted
read-only. The rest of that directory is not: it belongs to the herdr server
on your Mac. Settings in it that point at Mac paths, such as a Homebrew
`default_shell`, will not resolve in the container.

`herdr integration install claude` writes a hook script into `~/.claude/hooks`
and an entry into `~/.claude/settings.json`. Both are shared with your Mac, so
whichever side installs it, the other side runs the same hook too.

## Ports

Nothing in the container is reachable from outside unless you publish it. A
file named `.airlock` in the project folder lists the ports, one per line:

```
# a dev server, the same port on both sides
port 3000
# Mac port 8080 to container port 80
port 8080:80
```

`airlock add port 3000 8080:80` and `airlock remove port 3000` edit it for
you and refuse what would not work: a Mac port taken twice, a port out of
range, an address. Other lines and comments are left as they are.

They are published on the Mac's `127.0.0.1` only, never on the LAN, and there
is no way to ask for anything else. The service inside has to listen on
`0.0.0.0`, not `127.0.0.1`: the connection arrives over the container's
network interface, not its loopback.

The file belongs to you, not to the container: airlock mounts it read-only
over itself, so nothing running inside can add a port. If it does not exist,
the container could create it — which is why the worst it could do with that
is open a port on your Mac's localhost.

A container keeps the ports it was created with, so when the list changes the
next `claude` replaces the container instead of restarting it. Both `claude`
and `herdr` publish the same ports, so with ports in `.airlock` only one of
the two can run in a folder at a time.

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

Every start — the first one and every restart — runs the image entrypoint
with `CAP_NET_ADMIN` and `CAP_SETPCAP`, in a fresh network namespace. It runs
as uid 1000, not root: with `--userns keep-id` Podman starts it as you and
puts the two capabilities in its ambient and inheritable sets.

```sh
nft -f /etc/airlock/egress.nft
exec setpriv --reuid=1000 --regid=1000 --keep-groups \
    --inh-caps=-all --ambient-caps=-all \
    --bounding-set=-net_admin,-net_raw,-setpcap -- "$@"
```

The rules in `image/egress.nft` reject every private range (RFC1918, CGNAT,
link-local, loopback, multicast and the IPv6 equivalents). The one exception
is replies on connections that came in through a published port: they go back
to Podman's gateway, which is a private address. The rule takes only packets
in the reply direction of a connection the other side opened
(`ct direction reply`), so a connection the container opens itself never
matches it.

After the rules, two drops. Clearing the inheritable and ambient sets means
the command — Claude Code, herdr, your shell — runs with no capabilities at
all. Removing `NET_ADMIN`, `NET_RAW` and `SETPCAP` from the **bounding set**
is permanent and inherited by every later process, so even `sudo`'s root
cannot get them back and cannot touch the rules. Both are needed: the
bounding set only limits what a later exec can gain, not what a process
already holds, and Podman hands the capabilities over in exactly the sets it
does not cover. `CAP_SETPCAP` is what allows the drop itself. If `nft` fails,
the entrypoint exits and Claude never starts.

DNS uses `9.9.9.9` and `1.1.1.1` because your router's resolver sits in a
blocked range. IPv6 is off inside the container. Files created in the container
belong to you on the Mac (`--userns=keep-id`).

**Known gap:** if your router does port forwarding *and* hairpin NAT, those
ports are reachable from the container via your own public IP. That looks like
ordinary internet traffic and is not covered by these rules.

## Tests

`tests/acceptance.sh` checks the above against real containers: internet up,
private ranges down, a published port answering while its peer stays closed
to the container, `.airlock` read-only inside, `sudo nft flush ruleset`
denied, mount isolation, file ownership. It starts its own throwaway containers with the same flags, so it
does not touch any container of yours. `shellcheck` runs in CI.

## License

MIT
