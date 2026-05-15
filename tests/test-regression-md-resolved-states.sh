#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
regression="${repo_root}/regression.md"

if [[ ! -f "${regression}" ]]; then
  echo "FAIL regression.md state gate: missing ${regression}" >&2
  exit 1
fi

allowed_re='^solved$'
violations=()
start_marker='<!-- nix-file-loc:start -->'
end_marker='<!-- nix-file-loc:end -->'

while IFS=: read -r line text; do
  state="$(awk '{ if (match($0, /(^|[ |])state=[^ |`]*/)) { value = substr($0, RSTART, RLENGTH); sub(/^.*state=/, "", value); print value; } }' <<<"${text}")"
  [[ -n "${state}" ]] || continue

  if [[ ! "${state}" =~ ${allowed_re} ]]; then
    violations+=("${regression}:${line}: state=${state}: ${text}")
  fi
done < <(
  awk -v start="${start_marker}" -v end="${end_marker}" '
    $0 == start { in_loc = 1; next }
    $0 == end { in_loc = 0; next }
    !in_loc && /state=/ { print FNR ":" $0 }
  ' "${regression}"
)

if ((${#violations[@]} > 0)); then
  echo "FAIL regression.md state gate: unresolved regression states remain." >&2
  echo "Fix the owning bug, then update the entry to state=solved after evidence." >&2
  printf '%s\n' "${violations[@]}" >&2
  exit 1
fi

echo "PASS regression-md-resolved-states"
