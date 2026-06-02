#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: SMT-COMP-PROVENANCE-001
# GAMP-SCOPE: software-module-test

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
foreign_cwd="${NETWORK_FOREIGN_CWD:-/home/deadbeef/github/network-codex-agent}"

fail() {
  echo "$1" >&2
  exit 1
}

[[ -d "${foreign_cwd}" ]] || foreign_cwd="/tmp"

archive_json="$(mktemp)"
tmp_dir="$(mktemp -d)"
trap 'rm -f "${archive_json}"; rm -rf "${tmp_dir}"' EXIT

nix flake archive --json "path:${repo_root}" > "${archive_json}"
labs_root="$(jq -er '.inputs["network-labs"].path' "${archive_json}")"
intent="${labs_root}/examples/single-wan/intent.nix"
[[ -f "${intent}" ]] || fail "missing intent: ${intent}"

own_rev="$(git -C "${repo_root}" rev-parse HEAD)"
foreign_rev="$(git -C "${foreign_cwd}" rev-parse HEAD 2>/dev/null || true)"

(
  cd "${foreign_cwd}"
  OUTPUT_COMPILER_SIGNED_JSON="${tmp_dir}/foreign-signed.json" \
    nix run --no-warn-dirty --no-write-lock-file "path:${repo_root}#compile" -- "${intent}" \
    > "${tmp_dir}/foreign.json"
)

jq -e --arg foreign "${foreign_rev}" '
  .meta.compiler.name == "network-compiler"
  and (.meta.compiler.sourceNarHash // "") != ""
  and (
    (.meta.compiler.gitDirty == true and .meta.compiler.sourceLastModified == "unknown")
    or (.meta.compiler.gitDirty == false and (.meta.compiler.sourceLastModified | test("^[0-9]+$|^unknown$")))
  )
  and (
    ($foreign == "")
    or (.meta.compiler.gitRev != $foreign)
  )
' "${tmp_dir}/foreign.json" >/dev/null \
  || fail "compiler provenance used the foreign caller repository"

(
  cd "${repo_root}"
  OUTPUT_COMPILER_SIGNED_JSON="${tmp_dir}/own-signed.json" \
    nix run --no-warn-dirty --no-write-lock-file "path:${repo_root}#compile" -- "${intent}" \
    > "${tmp_dir}/own.json"
)

jq -e --arg own "${own_rev}" '
  .meta.compiler.name == "network-compiler"
  and .meta.compiler.gitRev == $own
  and (.meta.compiler.gitDirty | type == "boolean")
  and (
    (.meta.compiler.gitDirty == true and .meta.compiler.sourceLastModified == "unknown")
    or (.meta.compiler.gitDirty == false and (.meta.compiler.sourceLastModified | test("^[0-9]+$|^unknown$")))
  )
' "${tmp_dir}/own.json" >/dev/null \
  || fail "compiler provenance did not use the emitter repository"

echo "PASS emitter-provenance-repo-boundary"
