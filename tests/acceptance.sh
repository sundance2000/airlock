#!/usr/bin/env bash
#
# Acceptance tests for airlock (see README "Security model" and the spec §10).
#
# These tests are destructive in their own scratch directories only. They
# create containers and state under a temporary project directory inside
# $HOME, and remove both at the end.
#
# Run from anywhere:  ./tests/acceptance.sh
# Keep the scratch dirs for debugging:  KEEP=1 ./tests/acceptance.sh

set -uo pipefail

REPO_DIR=$(cd -P "$(dirname "$0")/.." && pwd)
AIRLOCK="${AIRLOCK_BIN:-$REPO_DIR/bin/airlock}"
export AIRLOCK_SHARE="${AIRLOCK_SHARE:-$REPO_DIR/share}"

PASS=0
FAIL=0
SKIP=0

pass() { PASS=$((PASS + 1)); printf '  ok    %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n' "$*"; }
skip() { SKIP=$((SKIP + 1)); printf '  skip  %s\n' "$*"; }
head2() { printf '\n== %s ==\n' "$*"; }

expect_ok() {
    local desc="$1" cmd="$2"
    if podman exec "$CONTAINER" bash -lc "$cmd" >/dev/null 2>&1; then
        pass "$desc"
    else
        fail "$desc (command failed but should succeed: $cmd)"
    fi
}

expect_fail() {
    local desc="$1" cmd="$2"
    if podman exec "$CONTAINER" bash -lc "$cmd" >/dev/null 2>&1; then
        fail "$desc (command succeeded but should fail: $cmd)"
    else
        pass "$desc"
    fi
}

cleanup() {
    if [ "${KEEP:-0}" = "1" ]; then
        printf '\nKEEP=1: leaving %s and %s behind\n' "$PROJ" "${PROJ2:-}"
        return
    fi
    [ -n "${PROJ:-}" ] && [ -d "$PROJ" ] && (cd "$PROJ" && yes | "$AIRLOCK" :reset >/dev/null 2>&1)
    [ -n "${PROJ2:-}" ] && [ -d "$PROJ2" ] && (cd "$PROJ2" && yes | "$AIRLOCK" :reset >/dev/null 2>&1)
    [ -n "${PROJ:-}" ] && rm -rf "$PROJ"
    [ -n "${PROJ2:-}" ] && rm -rf "$PROJ2"
}
trap cleanup EXIT

command -v podman >/dev/null 2>&1 || { printf 'podman not found\n' >&2; exit 2; }
[ -x "$AIRLOCK" ] || { printf 'not executable: %s\n' "$AIRLOCK" >&2; exit 2; }

PROJ="$HOME/.airlock-test-$$"
PROJ2="$HOME/.airlock-test2-$$"
mkdir -p "$PROJ" "$PROJ2"

head2 "bootstrap"
if (cd "$PROJ" && "$AIRLOCK" :doctor >/dev/null 2>&1); then
    pass "container and image bootstrap"
else
    # :doctor returns non-zero when the image is missing; force a build via shell
    (cd "$PROJ" && "$AIRLOCK" :shell </dev/null >/dev/null 2>&1) || true
    if (cd "$PROJ" && "$AIRLOCK" :doctor >/dev/null 2>&1); then
        pass "container and image bootstrap"
    else
        fail "container and image bootstrap"
    fi
fi

HASH=$(printf '%s' "$(cd "$PROJ" && pwd -P)" | shasum -a 256 | cut -c1-12)
SLUG=$(basename "$PROJ" | tr -cd 'a-zA-Z0-9_.-' | cut -c1-30)
CONTAINER="airlock-$SLUG-$HASH"
STATE="${XDG_DATA_HOME:-$HOME/.local/share}/airlock/$HASH"

if podman container exists "$CONTAINER"; then
    pass "container $CONTAINER exists"
else
    printf 'cannot continue without a container\n' >&2
    exit 1
fi

head2 "network: internet reachable, private networks blocked"
expect_ok   "https://api.anthropic.com reachable" \
            "curl -sSI -m 10 https://api.anthropic.com"
expect_fail "gvproxy host (192.168.127.254) blocked" \
            "curl -m 3 http://192.168.127.254"
expect_fail "host.containers.internal blocked" \
            "curl -m 3 http://host.containers.internal"
expect_fail "RFC1918 10/8 blocked" \
            "curl -m 3 http://10.0.0.1"
expect_fail "CGNAT/Tailscale 100.64/10 blocked" \
            "curl -m 3 http://100.64.0.1"
expect_fail "link-local 169.254/16 blocked" \
            "curl -m 3 http://169.254.169.254"

ROUTER=$(route -n get default 2>/dev/null | awk '/gateway:/{print $2}')
if [ -n "$ROUTER" ]; then
    expect_fail "router $ROUTER blocked" "curl -m 3 http://$ROUTER"
else
    skip "router unreachable test (no default gateway found)"
fi

LAN_IP=""
for iface in en0 en1 en2; do
    LAN_IP=$(ipconfig getifaddr "$iface" 2>/dev/null || true)
    [ -n "$LAN_IP" ] && break
done
if [ -n "$LAN_IP" ] && command -v python3 >/dev/null 2>&1; then
    PORT=8973
    python3 -m http.server "$PORT" --bind 0.0.0.0 >/dev/null 2>&1 &
    SRV_PID=$!
    sleep 1
    expect_fail "host service on $LAN_IP:$PORT blocked" \
                "curl -m 3 http://$LAN_IP:$PORT"
    expect_fail "host service via host.containers.internal:$PORT blocked" \
                "curl -m 3 http://host.containers.internal:$PORT"
    kill "$SRV_PID" 2>/dev/null || true
    wait "$SRV_PID" 2>/dev/null || true
else
    skip "host service test (no LAN IP or python3)"
fi

head2 "capabilities"
expect_fail "sudo nft flush ruleset denied (no NET_ADMIN)" \
            "sudo nft flush ruleset"
expect_ok   "sudo still works for package management" \
            "sudo -n true"

head2 "filesystem isolation"
expect_ok   "project directory is mounted at the same path" \
            "test -d '$PROJ'"
expect_fail "\$HOME of the mac is not visible" \
            "test -e '$HOME/.ssh' -o -e '$HOME/Library'"
expect_fail "no ssh agent socket" \
            "test -n \"\${SSH_AUTH_SOCK:-}\""
expect_fail "no podman/docker socket" \
            "test -S /var/run/docker.sock"

head2 "file ownership"
podman exec "$CONTAINER" bash -lc "touch '$PROJ/owner-probe'" >/dev/null 2>&1
if [ -f "$PROJ/owner-probe" ]; then
    owner=$(stat -f '%Su' "$PROJ/owner-probe" 2>/dev/null || stat -c '%U' "$PROJ/owner-probe")
    if [ "$owner" = "$(id -un)" ]; then
        pass "file created in the container belongs to $owner on the mac"
    else
        fail "file created in the container belongs to '$owner', expected '$(id -un)'"
    fi
    rm -f "$PROJ/owner-probe"
else
    fail "could not create a file from inside the container"
fi

head2 "persistence"
podman exec "$CONTAINER" bash -lc "mkdir -p ~/.npm-global/bin && echo hi > ~/persist-probe" >/dev/null 2>&1
podman exec "$CONTAINER" bash -ic "history -s airlock-history-probe; history -a" >/dev/null 2>&1
(cd "$PROJ" && "$AIRLOCK" :recreate >/dev/null 2>&1)
(cd "$PROJ" && "$AIRLOCK" :shell </dev/null >/dev/null 2>&1) || true
if podman exec "$CONTAINER" bash -lc "test -f ~/persist-probe" >/dev/null 2>&1; then
    pass "home survives :recreate"
else
    fail "home did not survive :recreate"
fi
if [ -f "$STATE/home/.bash_history" ] &&
   grep -q "airlock-history-probe" "$STATE/home/.bash_history" 2>/dev/null; then
    pass "shell history persists in the state directory"
else
    skip "shell history probe (non-interactive history is best effort)"
fi

head2 "two directories are independent"
(cd "$PROJ2" && "$AIRLOCK" :shell </dev/null >/dev/null 2>&1) || true
HASH2=$(printf '%s' "$(cd "$PROJ2" && pwd -P)" | shasum -a 256 | cut -c1-12)
CONTAINER2="airlock-$(basename "$PROJ2" | tr -cd 'a-zA-Z0-9_.-' | cut -c1-30)-$HASH2"
if [ "$HASH" != "$HASH2" ] && podman container exists "$CONTAINER2"; then
    pass "second directory gets its own container and state"
else
    fail "second directory did not get an independent container"
fi

head2 "refused start directories"
if (cd "$HOME" && "$AIRLOCK" :shell </dev/null >/dev/null 2>&1); then
    fail "start in \$HOME was allowed"
else
    pass "start in \$HOME refused"
fi
if (cd / && "$AIRLOCK" :shell </dev/null >/dev/null 2>&1); then
    fail "start in / was allowed"
else
    pass "start in / refused"
fi

head2 "fail-closed"
podman run --rm --network "container:$CONTAINER" --userns "container:$CONTAINER" \
    --user 0:0 --cap-add NET_ADMIN --entrypoint nft \
    "${AIRLOCK_IMAGE:-localhost/airlock:latest}" delete table inet airlock \
    >/dev/null 2>&1 ||
podman run --rm --network "container:$CONTAINER" \
    --user 0:0 --cap-add NET_ADMIN --entrypoint nft \
    "${AIRLOCK_IMAGE:-localhost/airlock:latest}" delete table inet airlock \
    >/dev/null 2>&1 || true

if (cd "$PROJ" && "$AIRLOCK" :shell </dev/null >/dev/null 2>&1); then
    fail "exec ran although the egress rules were removed"
else
    pass "no exec without egress rules (fail-closed)"
fi
if podman inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null | grep -q false; then
    pass "container was stopped when rules were missing"
else
    fail "container kept running without rules"
fi

printf '\n== summary ==\n'
printf 'passed: %s  failed: %s  skipped: %s\n' "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" -eq 0 ]
