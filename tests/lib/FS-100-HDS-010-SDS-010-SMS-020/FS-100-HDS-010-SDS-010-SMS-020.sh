#!/usr/bin/env bash
# GAMP-ID: FS-100-HDS-010-SDS-010-SMS-020
# GAMP-SCOPE: deterministic source identity construction proof
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
trace_id="FS-100-HDS-010-SDS-010-SMS-020"
shared_test="${repo_root}/tests/test-emitter-provenance-repo-boundary.sh"
# The provenance check needs a *foreign* revision, not a specific repository.
# Build a throwaway git fixture so the check is self-contained and never
# depends on another checkout being present.
foreign_cwd="${NETWORK_FOREIGN_CWD:-}"
foreign_fixture=""
if [[ -z "${foreign_cwd}" ]]; then
  foreign_fixture="$(mktemp -d)"
  git -C "${foreign_fixture}" init -q
  git -C "${foreign_fixture}" -c user.email=fixture@example.invalid -c user.name=fixture \
    commit -q --allow-empty -m provenance-fixture
  foreign_cwd="${foreign_fixture}"
fi
trap '[[ -n "${foreign_fixture:-}" ]] && rm -rf "${foreign_fixture}"' EXIT

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
