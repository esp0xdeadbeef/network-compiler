#!/usr/bin/env bash
# GAMP-ID: FS-470-HDS-010-SDS-010-SMS-040
# GAMP-SCOPE: software-module-test
# Construction test: a node's advertisement of, or answering for, a tenant or
# protected prefix is explicit intent, resolved by the compiler and never
# inferred (FS-470). An unknown tenant or an undeclared prefix fails closed.
set -euo pipefail

ROOT="${NETWORK_COMPILER_ROOT:-${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}}"
scratch_root="${TMPDIR:-/tmp}"
work_dir="$(mktemp -d "${scratch_root%/}/fs470-advertises.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT

nix run "$ROOT#compile" -- "$ROOT/tests/fixtures/fs470-advertises-satisfiable.nix" >"$work_dir/pos.json" 2>"$work_dir/pos.err"
resolved="$(jq -c '.sites.default.goodsite.topology.nodes."core-a".advertises' "$work_dir/pos.json")"
[ "$resolved" = '["10.20.10.0/24","fd42:dead:beef:10::/64"]' ] || {
  echo "FAIL: tenant advertisement was not resolved to concrete prefixes: ${resolved}" >&2
  exit 1; }
empty="$(jq -c '.sites.default.goodsite.topology.nodes."access".advertises' "$work_dir/pos.json")"
[ "$empty" = '[]' ] || {
  echo "FAIL: a node without an advertisement declaration must normalize to an empty list: ${empty}" >&2
  exit 1; }
echo "PASS fs470-advertises-satisfiable"

set +e
nix run "$ROOT#compile" -- "$ROOT/tests/negative/fs470-advertises-unknown-tenant.nix" >"$work_dir/unknown.txt" 2>&1
unknown_rc=$?
set -e
[ "$unknown_rc" -ne 0 ] || { echo "FAIL: advertising an unknown tenant must fail closed" >&2; exit 1; }
grep -q "FS-470" "$work_dir/unknown.txt" || {
  echo "FAIL: expected an FS-470 diagnostic for an unknown tenant" >&2
  cat "$work_dir/unknown.txt" >&2; exit 1; }
echo "PASS fs470-advertises-unknown-tenant"

set +e
nix run "$ROOT#compile" -- "$ROOT/tests/negative/fs470-advertises-undeclared-prefix.nix" >"$work_dir/undeclared.txt" 2>&1
undeclared_rc=$?
set -e
[ "$undeclared_rc" -ne 0 ] || { echo "FAIL: advertising an undeclared prefix must fail closed" >&2; exit 1; }
grep -q "FS-470" "$work_dir/undeclared.txt" || {
  echo "FAIL: expected an FS-470 diagnostic for an undeclared prefix" >&2
  cat "$work_dir/undeclared.txt" >&2; exit 1; }
echo "PASS fs470-advertises-undeclared-prefix"

echo "PASS FS-470-HDS-010-SDS-010-SMS-040 explicit node advertisement"
