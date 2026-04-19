#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

if command -v jq >/dev/null 2>&1; then
  jq_cmd=(jq)
else
  jq_cmd=(nix run nixpkgs#jq --)
fi

example_repo="$(
  nix flake archive --json "path:$ROOT" \
    | "${jq_cmd[@]}" -er '.inputs["network-labs"].path'
)"


find "$example_repo" -name 'intent.nix' -print0 |
  while IFS= read -r -d '' f; do
    echo ""
    echo "=== $f ==="
    nix run "path:$ROOT#compile" -- "$f" | jq -c
  done
