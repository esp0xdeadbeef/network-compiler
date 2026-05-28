#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: SMT-COMP-UPLINK-NAME-001
# GAMP-SCOPE: software-module-test

ROOT="${NETWORK_COMPILER_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
out="$(mktemp)"
trap 'rm -f "$out"' EXIT

set +e
nix run "$ROOT#compile" -- "$ROOT/tests/negative/duplicate-uplink-name.nix" >"$out" 2>&1
rc=$?
set -e

if [ "$rc" -eq 0 ]; then
echo "FAIL: duplicate site uplink names compiled successfully"
cat "$out"
exit 1
fi

if ! grep -q 'E_UPLINK_NAME_NOT_UNIQUE' "$out"; then
echo "FAIL: duplicate site uplink names did not raise E_UPLINK_NAME_NOT_UNIQUE"
cat "$out"
exit 1
fi

if ! grep -q "uplink name 'wan' must be unique across all core nodes in the site" "$out"; then
echo "FAIL: duplicate site uplink names did not explain site-wide ambiguity"
cat "$out"
exit 1
fi

echo "PASS: duplicate site uplink names fail as ambiguous"
