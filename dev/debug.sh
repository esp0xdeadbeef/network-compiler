
#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./dev/debug.sh                         # pure mode (no secrets)
#   ./dev/debug.sh ../../secrets/foo.yaml  # inject sopsData from this file
#
# We force --impure because debug-lib imports <nixpkgs/lib>
# and may rely on environment paths.

SOPS_FILE="${1:-}"

if [[ -n "${SOPS_FILE}" ]]; then
  if ! command -v sops >/dev/null 2>&1; then
    echo "error: sops not found in PATH" >&2
    exit 1
  fi

  if [[ ! -f "${SOPS_FILE}" ]]; then
    echo "error: SOPS file not found: ${SOPS_FILE}" >&2
    exit 1
  fi

  SOPS_JSON="$(sops -d --output-type json "${SOPS_FILE}")"
else
  SOPS_JSON='{}'
fi

for f in dev/debug-lib/[0-9][0-9]-*.nix; do
  base="$(basename "$f")"
  echo "==> $base"

  nix eval \
    --impure \
    --expr "let sopsData = builtins.fromJSON ''${SOPS_JSON}''; in import ./${f} { inherit sopsData; }" \
    --json | jq
done

