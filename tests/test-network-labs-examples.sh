#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if command -v jq >/dev/null 2>&1; then
  jq_cmd=(jq)
else
  jq_cmd=(nix run nixpkgs#jq --)
fi

archive_json="$(mktemp)"
trap 'rm -f "${archive_json}"' EXIT

nix flake archive --json "path:${repo_root}" > "${archive_json}"

labs_root="$(
  "${jq_cmd[@]}" -er '.inputs["network-labs"].path' "${archive_json}"
)"

examples_root="${labs_root}/examples"
[[ -d "${examples_root}" ]] || {
  echo "missing network-labs examples root: ${examples_root}" >&2
  exit 1
}

found=0
while IFS= read -r -d '' intent_path; do
  found=1
  rel="${intent_path#"${examples_root}/"}"
  echo "checking network-labs example: ${rel%/intent.nix}"
  nix run "${repo_root}#compile" -- "${intent_path}" | jq -e 'has("sites") and has("meta")' >/dev/null
done < <(find "${examples_root}" -mindepth 2 -maxdepth 2 -name intent.nix -print0 | sort -z)

if (( found == 0 )); then
  echo "no network-labs examples found under ${examples_root}" >&2
  exit 1
fi
