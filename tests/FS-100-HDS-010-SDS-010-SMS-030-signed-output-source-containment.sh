#!/usr/bin/env bash
# GAMP-ID: FS-100-HDS-010-SDS-010-SMS-030
# GAMP-SCOPE: signed-output source containment construction proof
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
trace_id="FS-100-HDS-010-SDS-010-SMS-030"
shared_test="${repo_root}/tests/test-emitter-provenance-repo-boundary.sh"
foreign_cwd="${NETWORK_FOREIGN_CWD:-${repo_root}/../network-codex-agent}"

fail() {
  echo "FAIL ${trace_id}: $*" >&2
  exit 1
}

[[ -x "${shared_test}" ]] || fail "missing executable shared provenance test"
[[ -d "${foreign_cwd}" ]] || fail "missing foreign repository for path-flake provenance check: ${foreign_cwd}"

grep -F 'OUTPUT_COMPILER_SIGNED_JSON="${tmp_dir}/foreign-signed.json"' "${shared_test}" >/dev/null \
  || fail "shared test does not prove controlled signed output path for foreign caller"
grep -F 'OUTPUT_COMPILER_SIGNED_JSON="${tmp_dir}/own-signed.json"' "${shared_test}" >/dev/null \
  || fail "shared test does not prove controlled signed output path for emitter repository"
grep -F "unset OUTPUT_COMPILER_SIGNED_JSON" "${shared_test}" >/dev/null \
  || fail "shared test does not exercise default signed output behavior"
grep -F '[[ ! -e "${repo_default_output}" ]]' "${shared_test}" >/dev/null \
  || fail "shared test does not reject default signed output inside emitter source tree"
grep -F 'runner-tmp/network-compiler/output-compiler-signed.json' "${shared_test}" >/dev/null \
  || fail "shared test does not prove default side artifact lands under TMPDIR"
grep -F 'compiler default signed output perturbed source identity' "${shared_test}" >/dev/null \
  || fail "shared test does not reject side-artifact source identity perturbation"
grep -F 'sourceNarHash == .[1].meta.compiler.sourceNarHash' "${shared_test}" >/dev/null \
  || fail "shared test does not compare source content identity across equivalent runs"
grep -F 'sourceLastModified == .[1].meta.compiler.sourceLastModified' "${shared_test}" >/dev/null \
  || fail "shared test does not compare source timestamp identity across equivalent runs"

NETWORK_REPO_DIRECT_TEST_OK=1 \
  NETWORK_FOREIGN_CWD="${foreign_cwd}" \
  bash "${shared_test}"

echo "PASS ${trace_id}: signed-output source containment"
