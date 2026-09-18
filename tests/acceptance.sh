#!/usr/bin/env bash
# Acceptance checks against a real container. Run from anywhere.
set -uo pipefail

AIRLOCK=$(cd -P "$(dirname "$0")/.." && pwd)/bin/airlock
PROJ="$HOME/airlock-test-$$"
FAIL=0

ok()   { printf '  ok    %s\n' "$1"; }
bad()  { printf '  FAIL  %s\n' "$1"; FAIL=1; }

# $1 description, $2 expected (pass|fail), $3 command inside the container
check() {
    local got=fail
    podman exec "$NAME" bash -lc "$3" >/dev/null 2>&1 && got=pass
    if [ "$got" = "$2" ]; then ok "$1"; else bad "$1 (got: $got)"; fi
}

mkdir -p "$PROJ"
trap 'cd "$PROJ" 2>/dev/null && echo y | "$AIRLOCK" :reset >/dev/null 2>&1; rm -rf "$PROJ"' EXIT

cd "$PROJ" || exit 1
"$AIRLOCK" :shell </dev/null >/dev/null 2>&1   # creates and starts the container
NAME="airlock-$(basename "$PROJ")-$(printf '%s' "$(pwd -P)" | shasum -a 256 | cut -c1-12)"
podman container exists "$NAME" || { echo "no container"; exit 1; }

echo "network"
check "internet reachable"          pass "curl -sSI -m 10 https://api.anthropic.com"
check "gvproxy host blocked"        fail "curl -m 3 http://192.168.127.254"
check "host.containers.internal blocked" fail "curl -m 3 http://host.containers.internal"
check "private 10/8 blocked"        fail "curl -m 3 http://10.0.0.1"
check "tailscale range blocked"     fail "curl -m 3 http://100.64.0.1"

echo "privileges"
check "cannot flush the rules"      fail "sudo nft flush ruleset"
check "sudo otherwise works"        pass "sudo -n true"

echo "filesystem"
check "project is mounted"          pass "test -d '$PROJ'"
check "mac home not visible"        fail "test -e '$HOME/Library'"

echo "ownership"
podman exec "$NAME" touch "$PROJ/probe" 2>/dev/null
if [ -f "$PROJ/probe" ] && [ "$(stat -f '%Su' "$PROJ/probe")" = "$(id -un)" ]; then
    ok "container files belong to me"
else
    bad "container files belong to me"
fi

exit "$FAIL"
