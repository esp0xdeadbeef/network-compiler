#!/usr/bin/env bash
# scripts/seed.sh — Compile an intent file and cache output as test fixtures.
#
# Usage:
#   scripts/seed.sh <intent.nix> [output-dir]
#
# Default output-dir: tests/fixtures/seeded/
#
# Compiles the given intent file through the network-compiler and writes
# the output JSON to a seed fixture directory. Re-running with the same
# intent overwrites the cached output.
#
# Used to regenerate test fixtures after intent changes.
set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

intent_path="${1:-}"
if [[ -z "${intent_path}" ]]; then
  echo "usage: $0 <intent.nix> [output-dir]" >&2
  exit 2
fi

if [[ ! -f "${intent_path}" ]]; then
  echo "error: intent file not found: ${intent_path}" >&2
  exit 1
fi

output_dir="${2:-${repo_root}/tests/fixtures/seeded}"
mkdir -p "${output_dir}"

intent_name="$(basename "${intent_path}" .nix)"
output_json="${output_dir}/${intent_name}.json"

echo "Compiling: ${intent_path}"
echo "Output:    ${output_json}"

nix run "path:${repo_root}#compile" -- "${intent_path}" |
  jq -S . > "${output_json}"

echo "Done. Fixture written to ${output_json}"
