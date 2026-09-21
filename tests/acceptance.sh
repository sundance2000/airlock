#!/usr/bin/env bash
# Acceptance checks against real containers. Run from anywhere.
set -uo pipefail

repo_dir=$(cd -P "$(dirname "$0")/.." && pwd)              # this checkout
image_name=localhost/airlock:latest                        # the same image airlock uses
project_dir="$HOME/airlock-test-$$"                        # throwaway project directory
failed=0                                                   # 1 once a check fails

ok()  { printf '  ok    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; failed=1; }

# A throwaway container with the same flags bin/airlock uses, running $1 in zsh.
in_container() {
    podman run --rm -i \
        --userns "keep-id:uid=1000,gid=1000" \
        --cap-add NET_ADMIN \
        --dns 9.9.9.9 --dns 1.1.1.1 \
        --sysctl net.ipv6.conf.all.disable_ipv6=1 \
        -v "$project_dir:$project_dir" -w "$project_dir" \
        "$image_name" zsh -c "$1"
}

# $1 description, $2 expected (pass|fail), $3 command inside the container
check() {
    local result=fail                                         # what actually happened
    in_container "$3" >/dev/null 2>&1 && result=pass
    if [ "$result" = "$2" ]; then ok "$1"; else bad "$1 (got: $result)"; fi
}

mkdir -p "$project_dir"
trap 'rm -rf "$project_dir"' EXIT
podman image exists "$image_name" || podman build -t "$image_name" -f "$repo_dir/image/Containerfile" "$repo_dir/image"

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
check "project is mounted"          pass "test -d '$project_dir'"
check "mac home not visible"        fail "test -e '$HOME/Library'"

echo "ownership"
in_container "touch '$project_dir/probe'" >/dev/null 2>&1
if [ -f "$project_dir/probe" ] && [ "$(stat -f '%Su' "$project_dir/probe")" = "$(id -un)" ]; then
    ok "container files belong to me"
else
    bad "container files belong to me"
fi

exit "$failed"
