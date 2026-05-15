# network-compiler Regression Notes

This file records current policy exceptions only. Keep entries exact and
current; do not use it as a session log.

## Nix File LOC States

The file-size guard requires every tracked Nix file over the soft limit to have
a current state and reason. Files at or above the hard limit fail immediately
and must be split before tests can pass.

<!-- nix-file-loc:start -->
235 flake.nix | policy=required | reason=flake app/test wiring is allowed as the only root-level Nix entrypoint above the soft limit
<!-- nix-file-loc:end -->

## Architecture Shape

- state=solved | target=core-to-core structural isolation invariant | evidence=2026-05-14 `NETWORK_REPO_DIRECT_TEST_OK=1 tests/test-canonical-traffic-paths.sh` and `NETWORK_REPO_DIRECT_TEST_OK=1 tests/check.sh` passed, including locked network-labs examples and `labs/lab-s-sigma/s-router-test-three-site` | reason=The compiler now hard-fails non-canonical topology links with `E_TOPO_NON_CANONICAL_STAGE_LINK`, including direct core-to-core and access-to-policy bypass links, and emits per-relation `trafficPaths` carrying canonical stage traversal, node path alternatives for multi-uplink relations, core path nodes, and a p2p isolation key. WAN cores, Nebula cores, simulated ISP cores, and similar core roles must not become a mesh; any traffic between cores must be expressed through policy-controlled delegated p2p lanes.
- state=solved | target=branch DNS canonical staged path | evidence=2026-05-14 late live route walk for branch-to-site-A mgmt DNS selected the canonical staged route in the live kernel on both branch and site-A sides; the later DNS loss occurred in Nebula/runtime return delivery, not because the compiler omitted the staged path. | reason=Do not add compiler topology exceptions or direct core shortcuts to fix provider/runtime packet loss. Future tests should keep asserting canonical access -> downstream-selector -> policy -> upstream-selector -> core traversal for cross-site DNS relations.
- state=policy-required | policy=required | target=s88-style Enterprise/Site/Unit/EquipmentModule/ControlModule layout | reason=compiler code must be organized by model responsibility, with top-level files limited to flakes, tests, entrypoints, and thin imports into s88-style responsibility folders; new policy or behavior must not be added as root-level blobs.
- state=policy-required | policy=required | target=no oversized implementation files | reason=Nix implementation files over 200 LOC must be split by concrete responsibility unless they are flake/test wiring or explicitly documented as a temporary regression with a split target.
- state=solved | target=network-pipeline-contract-audit compiler entrypoint | evidence=2026-05-14 `bash tests/check.sh` passed, including locked `network-labs` examples and `labs/lab-s-sigma/s-router-test-three-site` compiler input | reason=Current compiler audit found no renderer-style realization, route, firewall, or runtime invention in the compiler layer; compiler remains responsible for semantic normalization and canonical staged topology only.
- state=fixed-locally | target=overlay ingress policy references | evidence=2026-05-15 full-loop local build failed before live topology boot with `E_OVERLAY_DEFINED_WITHOUT_POLICY_RULES` for `esp.hetz` even though the new lab intent has policy relations from external `east-west` to WAN and service endpoints. `NETWORK_REPO_DIRECT_TEST_OK=1 tests/test-overlay-ingress-policy-reference.sh` covers an ingress-only overlay relation shape. | reason=An overlay that is used as a policy-controlled ingress source is still referenced by policy; the compiler gate must not require every overlay reference to be tenant-to-external egress.
