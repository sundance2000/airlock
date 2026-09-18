# airlock

Run **Claude Code** isolated in a Podman container: limited to the current
directory, with internet access but no access to your Mac or your LAN.

Every directory gets its own persistent container and state — run `airlock`
again in the same folder and you pick up exactly where you left off: same
Claude session, same installed tools, same shell history.

> `airlock` is an unofficial community tool. It is not affiliated with or
> endorsed by Anthropic.

---

## Why

Claude Code is useful precisely because it can run commands. On your Mac that
means it can also reach your SSH keys, your keychain, your other projects, the
Docker socket, your router's admin page and every service on your LAN — not
usually on purpose, but nothing stops it.

airlock puts a boundary around that:

* **Filesystem** — only the current directory is mounted. Nothing else of your
  home is visible.
* **Network** — the whole internet works; every private network (RFC1918,
  CGNAT/Tailscale, link-local, multicast, and the gvproxy range through which
  the Mac itself is reachable) is rejected.
* **Privileges** — `sudo apt install` works inside the container, but the
  container has no `NET_ADMIN`, so not even root in there can lift the network
  rules.

## Requirements

* macOS with [Podman](https://podman.io) ≥ 4.3 (`brew install podman`)
* A running Podman VM: `podman machine init` (once) and `podman machine start`

Docker, Linux hosts and Windows hosts are explicit non-goals for now.

## Install

```sh
git clone https://github.com/sundance2000/airlock.git
cd airlock
./install.sh
```

This installs `~/.local/bin/airlock` and the image files into
`~/.local/share/airlock/dist/`, and offers to create a `claude → airlock`
symlink so you can just type `claude`.

If you already have a native Claude Code (usually `~/.local/bin/claude`), the
installer warns you: the symlink only takes effect if its directory comes
**first** in your `PATH`. Check with `type -a claude`. The native binary
remains usable at its full path.

Make sure `~/.local/bin` is on your `PATH`:

```sh
export PATH="$HOME/.local/bin:$PATH"
```

## Usage

```sh
cd ~/code/my-project
airlock                 # start Claude Code here (continues the last session)
airlock --model opus    # any claude argument is passed through unchanged
airlock :shell          # a bash shell in the same container, alongside Claude
```

| Command | What it does |
| --- | --- |
| `airlock [args]` | Ensure the container, start Claude Code. Without arguments it uses `--continue` if a session exists. |
| `airlock :shell` | Bash in the same container, can run in parallel to Claude |
| `airlock :update` | Update Claude Code into the container home (`npm i -g @anthropic-ai/claude-code@latest`) |
| `airlock :stop` | Stop this directory's container |
| `airlock :recreate` | Delete the container, keep home/session/history |
| `airlock :reset` | Delete container **and** state for this directory (asks first) |
| `airlock :rebuild` | Rebuild the image (existing containers pick it up after `:recreate`) |
| `airlock :ls` | List all airlock containers with status and directory |
| `airlock :doctor` | Check podman, machine, image, rules and run network probes |
| `airlock :help` | Usage summary |

The `:` prefix keeps these apart from Claude Code's own flags and subcommands
(`claude mcp`, `claude update`, …).

Environment variables:

| Variable | Effect |
| --- | --- |
| `AIRLOCK_YOLO=1` | Adds `--dangerously-skip-permissions` to every `claude` start |
| `AIRLOCK_IMAGE` | Use a different image name (default `localhost/airlock:latest`) |
| `AIRLOCK_SHARE` | Directory holding `Containerfile`, `bashrc`, `egress.nft` |

## What persists, and where

State lives in `~/.local/share/airlock/<hash>/`, where `<hash>` is the first 12
characters of the SHA-256 of the resolved directory path:

```
~/.local/share/airlock/
├── dist/            # Containerfile, bashrc, egress.nft (installed copies)
├── oauth-token      # optional, see Authentication
└── a1b2c3d4e5f6/
    ├── home/        # mounted as /home/claude in the container
    └── path         # the directory this state belongs to
```

The container is created once (`sleep infinity`) and afterwards only started
and `exec`-ed into, so it is never thrown away implicitly:

* Tools installed with `sudo apt install` survive stop/start.
* Tools installed with `npm i -g` or `pip install --user` land in
  `/home/claude` and therefore survive even `:recreate`, because
  `NPM_CONFIG_PREFIX=/home/claude/.npm-global` and `~/.local/bin` come first in
  `PATH`.
* Claude's session transcripts live in `/home/claude/.claude/projects/…`.
* Bash history from `:shell` is appended to `/home/claude/.bash_history` after
  every command.

The directory is mounted **at the same path as on the host** (`-v "$PWD:$PWD"`).
That is deliberate: Claude Code derives its session directory from the encoded
working directory, so an identical path keeps sessions attached to the project.

Two notes on history:

* Commands that **Claude** runs do not go into the bash history — it does not
  use your interactive shell.
* Claude's own prompt history lives in `~/.claude.json` inside the container
  home and is therefore persistent as well.

Starting airlock in `/` or in your home directory is refused — mounting either
would defeat the point.

## Authentication

In order of precedence:

1. `CLAUDE_CODE_OAUTH_TOKEN` from your environment, if set.
2. `~/.local/share/airlock/oauth-token` — create it once with
   `claude setup-token` and save the token there to share one login across all
   directories:
   ```sh
   umask 077
   claude setup-token > ~/.local/share/airlock/oauth-token
   ```
3. Otherwise: log in on first start, per directory. The login is stored in that
   directory's persistent home.

`ANTHROPIC_API_KEY` is forwarded when set on the host.

Tokens are never baked into the image, never put into container labels and
never logged — they are passed at runtime via `podman exec -e` only.

## Security model

**What airlock protects against:** accidents and curiosity. A confused or
over-eager agent cannot read `~/.ssh`, cannot touch your other projects, cannot
reach your NAS, your router, your Home Assistant or a service you have running
on `localhost`.

**What it does not protect against:** a determined attacker with a container
escape. This is process isolation via rootless Podman, not a hypervisor
boundary, and the code inside runs with your user's privileges on the host as
far as the mounted directory goes. Do not treat airlock as a sandbox for
deliberately hostile code.

How the network rules work: the ruleset in `share/egress.nft` is applied inside
the container's network namespace by a short-lived helper container that has
`CAP_NET_ADMIN`. The airlock container itself runs with
`--cap-drop NET_ADMIN,NET_RAW`, so nothing inside it — including `sudo` — can
change or flush the rules. Rules are re-applied after every start (a new start
means a new namespace), and their presence is verified before every `exec`:
if the table is missing, the container is stopped and the command aborts.
**No exec without active rules.**

DNS uses public resolvers (`9.9.9.9`, `1.1.1.1`) because the resolver handed
out by your router lives in the blocked ranges. IPv6 is disabled inside the
container so your Mac cannot be reached over a global v6 address.

### Known gap

If your router does port forwarding **and** supports hairpin NAT, services
behind those forwarded ports are reachable from inside the container via your
own public IP address. That traffic looks like ordinary internet traffic and is
not covered by the private-range rules. If that matters to you, do not forward
ports you care about, or restrict them at the router.

File ownership: `--userns=keep-id:uid=1000,gid=1000` maps your host user to the
container user `claude`, so files created inside the container belong to you on
the Mac.

## Tests

`tests/acceptance.sh` runs the acceptance criteria against real containers:
internet reachable, router/LAN/host/gvproxy blocked, `sudo nft flush ruleset`
denied, mount isolation, file ownership, persistence across `:recreate`,
independence of two directories, refusal to start in `$HOME` and `/`, and the
fail-closed behaviour when the rules are removed.

```sh
./tests/acceptance.sh
```

It creates and removes its own scratch directories under `$HOME`
(`KEEP=1` keeps them for debugging). `shellcheck` runs in CI over `bin/airlock`,
`install.sh` and the test script.

## Design decisions

* **Shell: bash 3.2.** The script runs on the bash that ships with macOS — no
  `mapfile`, no associative arrays, no `${var,,}`. That avoids depending on a
  Homebrew bash or on zsh-only syntax. Hashing uses `shasum -a 256`.
* **License: MIT.**
* **`AIRLOCK_YOLO`.** `--dangerously-skip-permissions` is available but opt-in
  per invocation/shell (`AIRLOCK_YOLO=1`), not a default and not a persisted
  setting — inside the airlock the blast radius is the project directory, but
  it should still be a conscious choice.
* **Name.** The tool is called `airlock`; "claude" appears neither in the repo
  name nor in the binary name. The optional `claude` symlink is a local
  convenience the user opts into.

## Repository layout

```
bin/airlock          main script
share/Containerfile  image definition
share/bashrc         history + prompt inside the container
share/egress.nft     network rules
install.sh           install into ~/.local, optional `claude` symlink
tests/               acceptance tests
```

## Non-goals (for now)

* Docker as the engine, Linux or Windows hosts
* Domain allowlists or an egress proxy — the rule is "internet yes, private no"
* Multiple agents (Codex, Gemini …) or git-worktree workflows
* Forwarding git credentials or SSH keys into the container

## License

MIT — see [LICENSE](LICENSE).
