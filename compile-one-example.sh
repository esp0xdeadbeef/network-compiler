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

example="${1:-$example_repo/examples/multi-wan/intent.nix}"

nix run "path:$ROOT#compile" -- "$example"
