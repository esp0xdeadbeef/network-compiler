# network-compiler Regression Notes

This file records current policy exceptions only. Keep entries exact and
current; do not use it as a session log.

## Nix File LOC States

The file-size guard requires every tracked Nix file over the soft limit to have
a current state and reason. Files at or above the hard limit fail immediately
and must be split before tests can pass.

<!-- nix-file-loc:start -->
235 flake.nix | state=watch | reason=flake app/test wiring is allowed as the only root-level Nix entrypoint above the soft limit
<!-- nix-file-loc:end -->

## Architecture Shape

- state=fixed-locally | target=core-to-core structural isolation invariant | evidence=2026-05-14 `NETWORK_REPO_DIRECT_TEST_OK=1 tests/test-canonical-traffic-paths.sh` and `NETWORK_REPO_DIRECT_TEST_OK=1 tests/check.sh` passed, including locked network-labs examples and `labs/lab-s-sigma/s-router-test-three-site` | reason=The compiler now hard-fails non-canonical topology links with `E_TOPO_NON_CANONICAL_STAGE_LINK`, including direct core-to-core and access-to-policy bypass links, and emits per-relation `trafficPaths` carrying canonical stage traversal, node path alternatives for multi-uplink relations, core path nodes, and a p2p isolation key. WAN cores, Nebula cores, simulated ISP cores, and similar core roles must not become a mesh; any traffic between cores must be expressed through policy-controlled delegated p2p lanes.
- state=required | target=s88-style Enterprise/Site/Unit/EquipmentModule/ControlModule layout | reason=compiler code must be organized by model responsibility, with top-level files limited to flakes, tests, entrypoints, and thin imports into s88-style responsibility folders; new policy or behavior must not be added as root-level blobs.
- state=required | target=no oversized implementation files | reason=Nix implementation files over 200 LOC must be split by concrete responsibility unless they are flake/test wiring or explicitly documented as a temporary regression with a split target.
- state=verified | target=network-pipeline-contract-audit compiler entrypoint | evidence=2026-05-14 `bash tests/check.sh` passed, including locked `network-labs` examples and `labs/lab-s-sigma/s-router-test-three-site` compiler input | reason=Current compiler audit found no renderer-style realization, route, firewall, or runtime invention in the compiler layer; compiler remains responsible for semantic normalization and canonical staged topology only.
