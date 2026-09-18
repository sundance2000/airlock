#!/usr/bin/env bash
# Acceptance checks against real containers. Run from anywhere.
set -uo pipefail

AIRLOCK=$(cd -P "$(dirname "$0")/.." && pwd)/bin/airlock   # the script under test
PROJ="$HOME/airlock-test-$$"                               # throwaway project directory
FAIL=0                                                     # non-zero once a check fails

ok()  { printf '  ok    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; FAIL=1; }

# $1 description, $2 expected (pass|fail), $3 command inside the container
check() {
    local got=fail                                         # what actually happened
    (cd "$PROJ" && "$AIRLOCK" shell -c "$3") >/dev/null 2>&1 && got=pass
    if [ "$got" = "$2" ]; then ok "$1"; else bad "$1 (got: $got)"; fi
}

mkdir -p "$PROJ"
HASH=$(printf '%s' "$(cd "$PROJ" && pwd -P)" | shasum -a 256 | cut -c1-12)  # its state id
NAME="airlock-$(basename "$PROJ")-$HASH"                                    # its containers
trap 'podman rm -f "$NAME" "$NAME-shell" >/dev/null 2>&1;
      rm -rf "$PROJ" "${XDG_DATA_HOME:-$HOME/.local/share}/airlock/$HASH"' EXIT

echo "network"
check "internet reachable"          pass "curl -sSI -m 10 https://api.anthropic.com"
check "gvproxy host blocked"        fail "curl -m 3 http://192.168.127.254"
check "host.containers.internal blocked" fail "curl -m 3 http://host.containers.internal"
check "private 10/8 blocked"        fail "curl -m 3 http://10.0.0.1"
check "tailscale range blocked"     fail "curl -m 3 http://100.64.0.1"

echo "privileges"
check "cannot flush the rules"      fail "sudo nft flush ruleset"
check "cannot add back NET_ADMIN"   fail "sudo nft list ruleset"
check "sudo otherwise works"        pass "sudo -n true"

echo "filesystem"
check "project is mounted"          pass "test -d '$PROJ'"
check "mac home not visible"        fail "test -e '$HOME/Library'"

echo "ownership"
(cd "$PROJ" && "$AIRLOCK" shell -c "touch '$PROJ/probe'") >/dev/null 2>&1
if [ -f "$PROJ/probe" ] && [ "$(stat -f '%Su' "$PROJ/probe")" = "$(id -un)" ]; then
    ok "container files belong to me"
else
    bad "container files belong to me"
fi

echo "lifetime"
if [ -z "$(podman ps -q --filter "name=$NAME")" ]; then
    ok "no container left running"
else
    bad "a container is still running"
fi

exit "$FAIL"
