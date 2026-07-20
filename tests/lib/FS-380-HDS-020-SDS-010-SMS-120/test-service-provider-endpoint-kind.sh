#!/usr/bin/env bash
# GAMP-ID: FS-380-HDS-020-SDS-010-SMS-120
# GAMP-SCOPE: compiler construction guard for router-owned service provider endpoints
set -euo pipefail

ROOT="${NETWORK_COMPILER_ROOT:-${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}}"

if [[ "${NETWORK_REPO_SWEEP:-0}" != "1" && "${NETWORK_REPO_DIRECT_TEST_OK:-0}" != "1" ]]; then
  echo "WARN: direct repo tests are partial; set NETWORK_REPO_DIRECT_TEST_OK=1 for intentional focused runs, or run the locked full network-* sweep plus live validation." >&2
fi

fixture="${ROOT}/tests/fixtures/service-provider-endpoint.nix"
out="$(mktemp)"
trap 'rm -f "${out}"' EXIT

nix run "${ROOT}#compile" -- "${fixture}" >"${out}"

jq -e '
  .sites.esp0xdeadbeef."site-a" as $site
  | ($site.services[] | select(.name == "access-dns" and .providers == ["access-dns"]))
  and ($site.consumedInterfaces.clients == [])
' "${out}" >/dev/null

echo "PASS service provider ownership endpoint is accepted without host/client consumption"
