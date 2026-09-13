#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-030-HDS-010-SDS-030-SMS-010
# GAMP-SCOPE: software-module-test
#
# mustTraverse is an ASSERTION, not a path input. The stages it names must
# already be in the derived canonical overlay path. A supplied stage the
# canonical fabric does not traverse fails closed
# (E_OVERLAY_MUST_TRAVERSE_UNSATISFIED), and a satisfied assertion compiles.

ROOT="${NETWORK_COMPILER_ROOT:-${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}}"

# Negative: mustTraverse names a stage NOT in the derived canonical path.
out="$(mktemp)"
err="$(mktemp)"
set +e
nix run "$ROOT#compile" -- "$ROOT/tests/negative/overlay-must-traverse-unsatisfied.nix" >"$out" 2>"$err"
rc=$?
set -e
if [[ "$rc" -eq 0 ]]; then
  echo "FAIL overlay-must-traverse-assertion: unsatisfied mustTraverse compiled" >&2
  cat "$out" >&2
  rm -f "$out" "$err"
  exit 1
fi
if ! grep -Fq "E_OVERLAY_MUST_TRAVERSE_UNSATISFIED" "$err"; then
  echo "FAIL overlay-must-traverse-assertion: did not emit E_OVERLAY_MUST_TRAVERSE_UNSATISFIED" >&2
  cat "$err" >&2
  rm -f "$out" "$err"
  exit 1
fi
rm -f "$out" "$err"

# Positive: mustTraverse = [ "policy" ] is satisfied by the derived path.
pos_out="$(mktemp)"
nix run "$ROOT#compile" -- "$ROOT/tests/fixtures/examples/single-wan-with-nebula-any-to-any-fw/intent.nix" >"$pos_out"
jq -e 'has("sites") and has("meta")' "$pos_out" >/dev/null || {
  echo "FAIL overlay-must-traverse-assertion: satisfied mustTraverse fixture did not compile" >&2
  cat "$pos_out" >&2
  rm -f "$pos_out"
  exit 1
}
rm -f "$pos_out"

echo "PASS overlay-must-traverse-assertion"
