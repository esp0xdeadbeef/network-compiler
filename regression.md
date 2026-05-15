# network-compiler Regression Notes

This file records current policy exceptions only. Keep entries exact and
current; do not use it as a session log.

## Nix File LOC States

The file-size guard requires every tracked Nix file over the soft limit to have
a current state and reason. Files at or above the hard limit fail immediately
and must be split before tests can pass.
`flake.nix` and `flake.lock` are ignored by this LOC guard because they are
often mechanically large, but they should stay essential-only: root app/test
wiring, inputs, and lock metadata belong there, not implementation logic.

<!-- nix-file-loc:start -->
<!-- nix-file-loc:end -->

## Architecture Shape

- state=solved | target=core-to-core structural isolation invariant | evidence=2026-05-14 `NETWORK_REPO_DIRECT_TEST_OK=1 tests/test-canonical-traffic-paths.sh` and `NETWORK_REPO_DIRECT_TEST_OK=1 tests/check.sh` passed, including locked network-labs examples and `labs/lab-s-sigma/s-router-test-three-site` | reason=The compiler now hard-fails non-canonical topology links with `E_TOPO_NON_CANONICAL_STAGE_LINK`, including direct core-to-core and access-to-policy bypass links, and emits per-relation `trafficPaths` carrying canonical stage traversal, node path alternatives for multi-uplink relations, core path nodes, and a p2p isolation key. WAN cores, Nebula cores, simulated ISP cores, and similar core roles must not become a mesh; any traffic between cores must be expressed through policy-controlled delegated p2p lanes.
- state=solved | target=branch DNS canonical staged path | evidence=2026-05-14 late live route walk for branch-to-site-A mgmt DNS selected the canonical staged route in the live kernel on both branch and site-A sides; the later DNS loss occurred in Nebula/runtime return delivery, not because the compiler omitted the staged path. | reason=Do not add compiler topology exceptions or direct core shortcuts to fix provider/runtime packet loss. Future tests should keep asserting canonical access -> downstream-selector -> policy -> upstream-selector -> core traversal for cross-site DNS relations.
- state=solved | policy=required | target=s88-style Enterprise/Site/Unit/EquipmentModule/ControlModule layout | evidence=2026-05-15 service-provider validation was split from `lib/stages/build-model.nix` into `lib/stages/validate-service-providers.nix` instead of adding more root-level stage logic. | reason=compiler code must be organized by model responsibility, with top-level files limited to flakes, tests, entrypoints, and thin imports into focused responsibility files; new policy or behavior must not be added as root-level blobs.
- state=solved | policy=required | target=no oversized implementation files | evidence=2026-05-15 `NETWORK_REPO_DIRECT_TEST_OK=1 bash tests/test-nix-file-loc.sh` passed after `flake.nix` and `flake.lock` were hardignored and `lib/stages/build-model.nix` was reduced below the 200 LOC soft limit by extracting `lib/stages/validate-service-providers.nix`. | reason=Nix implementation files over 200 LOC must be split by concrete responsibility; watch-state notes are not accepted and the guard raises `FIX IT.`
- state=solved | target=network-pipeline-contract-audit compiler entrypoint | evidence=2026-05-14 `bash tests/check.sh` passed, including locked `network-labs` examples and `labs/lab-s-sigma/s-router-test-three-site` compiler input | reason=Current compiler audit found no renderer-style realization, route, firewall, or runtime invention in the compiler layer; compiler remains responsible for semantic normalization and canonical staged topology only.
- state=solved | target=service-provider ownership hard-fail | evidence=2026-05-15 `NETWORK_REPO_DIRECT_TEST_OK=1 bash tests/test-canonical-traffic-paths.sh` passed, `nix run .#compile -- tests/negative/unknown-service-provider.nix` failed with `E_CONTRACT_UNKNOWN_SERVICE_PROVIDER`, and the locked `network-labs` sweep passed after the lab/example service ownership fixes. | reason=The compiler now raises a hard error for tenant-origin service providers missing from local ownership endpoints, while allowing remote providers only for services reached exclusively from external ingress relations.
- state=solved | target=overlay ingress policy references | evidence=2026-05-15 `NETWORK_REPO_DIRECT_TEST_OK=1 bash tests/test-overlay-ingress-policy-reference.sh` passed and `nix run .#compile -- /home/deadbeef/github/network-labs/labs/lab-s-sigma/s-router-test-three-site/intent.nix` compiled successfully. | reason=An overlay that is used as a policy-controlled ingress source is referenced by policy; the compiler gate must accept external-to-WAN/service overlay ingress relations instead of requiring tenant-to-external egress only.
