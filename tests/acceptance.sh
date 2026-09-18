#!/usr/bin/env bash
# Acceptance checks against real containers. Run from anywhere.
set -uo pipefail

REPO=$(cd -P "$(dirname "$0")/.." && pwd)                  # the repo under test
IMAGE="${AIRLOCK_IMAGE:-localhost/airlock:latest}"         # same image airlock uses
PROJ="$HOME/airlock-test-$$"                               # throwaway project directory
FAIL=0                                                     # non-zero once a check fails

ok()  { printf '  ok    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; FAIL=1; }

# A throwaway container with the same flags bin/airlock uses, running $1 in zsh.
box() {
    podman run --rm -i \
        --userns "keep-id:uid=1000,gid=1000" \
        --cap-add NET_ADMIN \
        --dns 9.9.9.9 --dns 1.1.1.1 \
        --sysctl net.ipv6.conf.all.disable_ipv6=1 \
        -v "$PROJ:$PROJ" -w "$PROJ" \
        "$IMAGE" zsh -c "$1"
}

# $1 description, $2 expected (pass|fail), $3 command inside the container
check() {
    local got=fail                                         # what actually happened
    box "$3" >/dev/null 2>&1 && got=pass
    if [ "$got" = "$2" ]; then ok "$1"; else bad "$1 (got: $got)"; fi
}

mkdir -p "$PROJ"
trap 'rm -rf "$PROJ"' EXIT
podman image exists "$IMAGE" || podman build -t "$IMAGE" -f "$REPO/share/Containerfile" "$REPO/share"

echo "network"
check "internet reachable"          pass "curl -sSI -m 10 https://api.anthropic.com"
check "gvproxy host blocked"        fail "curl -m 3 http://192.168.127.254"
check "host.containers.internal blocked" fail "curl -m 3 http://host.containers.internal"
check "private 10/8 blocked"        fail "curl -m 3 http://10.0.0.1"
check "tailscale range blocked"     fail "curl -m 3 http://100.64.0.1"

echo "privileges"
check "runs as uid 1000"            pass "test \$(id -u) -eq 1000"
check "cannot flush the rules"      fail "sudo nft flush ruleset"
check "cannot even read them"       fail "sudo nft list ruleset"
check "sudo otherwise works"        pass "sudo -n true"

echo "filesystem"
check "project is mounted"          pass "test -d '$PROJ'"
check "mac home not visible"        fail "test -e '$HOME/Library'"

echo "ownership"
box "touch '$PROJ/probe'" >/dev/null 2>&1
if [ -f "$PROJ/probe" ] && [ "$(stat -f '%Su' "$PROJ/probe")" = "$(id -un)" ]; then
    ok "container files belong to me"
else
    bad "container files belong to me"
fi

exit "$FAIL"
