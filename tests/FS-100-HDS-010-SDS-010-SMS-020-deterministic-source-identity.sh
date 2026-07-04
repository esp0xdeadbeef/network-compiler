#!/usr/bin/env bash
# GAMP-ID: FS-100-HDS-010-SDS-010-SMS-020
# GAMP-SCOPE: deterministic source identity construction proof
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
trace_id="FS-100-HDS-010-SDS-010-SMS-020"
shared_test="${repo_root}/tests/test-emitter-provenance-repo-boundary.sh"
foreign_cwd="${NETWORK_FOREIGN_CWD:-${repo_root}/../network-codex-agent}"

fail() {
  echo "FAIL ${trace_id}: $*" >&2
  exit 1
}

[[ -x "${shared_test}" ]] || fail "missing executable shared provenance test"
[[ -d "${foreign_cwd}" ]] || fail "missing foreign repository for path-flake provenance check: ${foreign_cwd}"

grep -F "sourceNarHash" "${shared_test}" >/dev/null \
  || fail "shared test does not assert deterministic source hash"
grep -F "sourceLastModified" "${shared_test}" >/dev/null \
  || fail "shared test does not assert source timestamp policy"
grep -F "gitDirty == true and .meta.compiler.sourceLastModified == \"unknown\"" "${shared_test}" >/dev/null \
  || fail "shared test does not reject volatile dirty path-flake timestamps"
grep -F "sourceNarHash == .[1].meta.compiler.sourceNarHash" "${shared_test}" >/dev/null \
  || fail "shared test does not compare source identity across equivalent runs"

NETWORK_REPO_DIRECT_TEST_OK=1 \
  NETWORK_FOREIGN_CWD="${foreign_cwd}" \
  bash "${shared_test}"

echo "PASS ${trace_id}: deterministic source identity"
