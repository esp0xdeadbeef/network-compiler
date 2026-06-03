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
repo_default_output="${repo_root}/output-compiler-signed.json"
repo_default_backup=""
if [[ -e "${repo_default_output}" ]]; then
  repo_default_backup="${tmp_dir}/preexisting-output-compiler-signed.json"
  mv "${repo_default_output}" "${repo_default_backup}"
fi

cleanup() {
  if [[ -n "${repo_default_backup}" ]]; then
    rm -f "${repo_default_output}"
    mv "${repo_default_backup}" "${repo_default_output}"
  else
    rm -f "${repo_default_output}"
  fi
  rm -f "${archive_json}"
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

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

(
  cd "${repo_root}"
  unset OUTPUT_COMPILER_SIGNED_JSON
  export TMPDIR="${tmp_dir}/runner-tmp"
  mkdir -p "${TMPDIR}"
  nix run --no-warn-dirty --no-write-lock-file "path:${repo_root}#compile" -- "${intent}" \
    > "${tmp_dir}/default-one.json"
  nix run --no-warn-dirty --no-write-lock-file "path:${repo_root}#compile" -- "${intent}" \
    > "${tmp_dir}/default-two.json"
)

[[ ! -e "${repo_default_output}" ]] \
  || fail "compiler default signed output was written into the emitter repository"

[[ -s "${tmp_dir}/runner-tmp/network-compiler/output-compiler-signed.json" ]] \
  || fail "compiler default signed output side artifact was not written under TMPDIR"

jq -s -e '
  .[0].meta.compiler.name == "network-compiler"
  and .[1].meta.compiler.name == "network-compiler"
  and .[0].meta.compiler.sourceNarHash == .[1].meta.compiler.sourceNarHash
  and .[0].meta.compiler.sourceLastModified == .[1].meta.compiler.sourceLastModified
' "${tmp_dir}/default-one.json" "${tmp_dir}/default-two.json" >/dev/null \
  || fail "compiler default signed output perturbed source identity"

echo "PASS emitter-provenance-repo-boundary"
