#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-322-HDS-010-SDS-010-SMS-020
# GAMP-SCOPE: software-module-test
# Construction test: an ordered multi-scope selection resolves in declared
# order (precedence), not from member order.

ROOT="${NETWORK_COMPILER_ROOT:-${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}}"
scratch_root="${TMPDIR:-/tmp}"
work_dir="$(mktemp -d "${scratch_root%/}/fs322-selection.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT

nix run "$ROOT#compile" -- "$ROOT/tests/fixtures/fs322-multi-select.nix" >"$work_dir/out.json" 2>"$work_dir/err.txt" || {
  echo "FAIL: multi-select fixture must compile" >&2
  cat "$work_dir/err.txt" >&2
  exit 1
}

order="$(jq -r '(.sites | to_entries[0].value | to_entries[0].value.topology.nodes.access.selects // []) | map(.scope) | join(",")' "$work_dir/out.json")"
if [ "$order" != "core-a,core-b" ]; then
  echo "FAIL: selection order not preserved for precedence; got '${order}'" >&2
  exit 1
fi

echo "PASS FS-322-HDS-010-SDS-010-SMS-020 scope selection resolution"
