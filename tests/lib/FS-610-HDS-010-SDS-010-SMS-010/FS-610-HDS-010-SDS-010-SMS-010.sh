#!/usr/bin/env bash
# GAMP-ID: FS-610-HDS-010-SDS-010-SMS-010
# GAMP-SCOPE: software-module-test
#
# SPEC:   GAMP/SMS/FS-610-HDS-010-SDS-010-SMS-010.md
# OWNER:  network-compiler
# MODULE: Cross-Scope Discovery Boundary Validation
#
# THIS TEST IS EXPECTED TO FAIL. The specification exists; the module does not.
# Do not weaken the test to make it pass — implement the module.
#
# Predicates taken from the SMS:
#   P1  Every cross-scope discovery relationship names requester scope, responder
#       scope, service type, protocol family, direction, relay or proxy role, and
#       maximum propagation boundary.
#   P2  Diagnostics are emitted for missing or ambiguous relay, proxy, reflection
#       or flooding inputs.
#
# Seeded negatives the SMS requires:
#   SN1  A cross-VLAN discovery relationship (`trusted` -> `printer-scope`,
#        service `ipp`, family `mdns`) that omits relay/proxy role and maximum
#        propagation boundary is rejected with
#        `INCOMPLETE_DISCOVERY_BOUNDARY` naming the missing fields, and emits no
#        scoped discovery-boundary contract. Adding `relayRole` and
#        `maxPropagationBoundary` passes.
#   SN2  A unicast route existing between the same scopes with no discovery relay,
#        proxy or reflection boundary is rejected with
#        `UNICAST_ROUTE_NOT_DISCOVERY_BOUNDARY` rather than emitting a multicast
#        or broadcast discovery boundary.
#
# To implement: add the boundary validator with those two diagnostic codes and the
# required-field set, at the point where discovery relationships enter the model.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/direct-test-guard.sh"

fail() { echo "FAIL cross-scope-discovery-boundary: $*" >&2; exit 1; }

search_roots=("${repo_root}/lib" "${repo_root}/src")

# SN1: the incomplete-boundary diagnostic named by the SMS.
if ! grep -rq 'INCOMPLETE_DISCOVERY_BOUNDARY' "${search_roots[@]}" --include=*.nix 2>/dev/null; then
  fail "SN1 no INCOMPLETE_DISCOVERY_BOUNDARY rejection exists for a discovery relationship missing its relay/proxy role or propagation boundary"
fi

# SN2: the unicast-route-is-not-a-boundary diagnostic named by the SMS.
if ! grep -rq 'UNICAST_ROUTE_NOT_DISCOVERY_BOUNDARY' "${search_roots[@]}" --include=*.nix 2>/dev/null; then
  fail "SN2 no UNICAST_ROUTE_NOT_DISCOVERY_BOUNDARY rejection exists; a unicast route can currently stand in for multicast/broadcast discovery authority"
fi

# P1: the required-field set. Checked per field so the failure names what is
# missing from the contract rather than only that the test failed.
missing=""
for field in 'requesterScope' 'responderScope' 'serviceType' 'protocolFamily' 'direction' 'relayRole' 'maxPropagationBoundary'; do
  grep -rqE "\\b${field}\\b" "${search_roots[@]}" --include=*.nix 2>/dev/null || missing="${missing} ${field}"
done
if [[ -n "${missing}" ]]; then
  fail "P1 the discovery-boundary contract does not name:${missing}"
fi

# P2: ambiguity must be diagnosed, not resolved by a default.
if ! grep -rqiE 'ambiguous' "${search_roots[@]}" --include=*.nix 2>/dev/null; then
  fail "P2 no ambiguity diagnostic exists for relay, proxy, reflection or flooding inputs"
fi

echo "PASS cross-scope-discovery-boundary"
