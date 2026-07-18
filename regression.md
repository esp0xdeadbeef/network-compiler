# Regression Notes

<!-- nix-file-loc:start -->
261 lib/stages/compiled-services.nix | state=split-required | reason=FS-590-SMS-040 discovery authority inference denial + FS-630-SMS-020 printer payload auth module wired; extract printer+media payload auth modules and discovery-authority module to shared boundary
217 lib/stages/source-audit.nix | state=split-required | reason=source-audit diagnostics module growing with per-layer context; extract layer-specific audit helpers to per-layer modules
<!-- nix-file-loc:end -->

- FS-030-HDS-010-SDS-020-SMS-010 selector-fanout policy-bypass classification corrected | state=solved | evidence=tests/test-FS-030-HDS-010-SDS-020-SMS-010.sh | notes=shared upstream-selector multi-core fanout and shared downstream-selector multi-access fanout are valid topology and do not create traffic-path authority without modeled relations
- FS-620-HDS-010-SDS-010-SMS-010 compiler isolation classification construction proof restored | state=solved | evidence=tests/test-FS-620-HDS-010-SDS-010-SMS-010.sh

## FS-525 / FS-540 named recursive DNS contract

- state=open
- owner: network-compiler
- scope: FS-525-HDS-010-SDS-010-SMS-010 and FS-540-HDS-010-SDS-010-SMS-010 through SMS-045
- first-bad-artifact: The 2026-07-18 `s-router-prod` pipeline input declares `recursiveDnsIntent` and `localDnsSharingIntent` with a named `core-dns` provider, requester-to-resolver bindings, dual-stack requirements, an explicit resolver path, and an egress selector. The compiler output retains those fields only incidentally through the original site value; it neither normalizes them as a compiler-owned contract nor emits the specified deterministic fail-closed diagnostics for missing, literal, ambiguous, family-incomplete, or unstable bindings.
- required-fix: Validate and normalize the named DNS service, provider-node, requester, resolver-path, recursion mode, local-authority boundary, and egress-selection references. Emit privacy-safe deterministic warning records containing modeled identifiers only. Do not resolve concrete listener, upstream, or protected endpoint addresses in the compiler.
- evidence: Add a focused compiler construction test using the FS-525/FS-540 lab source. Seeded negatives must prove each warning classification and stable ordering without public or protected address material.
