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

- state=required | target=s88-style Enterprise/Site/Unit/EquipmentModule/ControlModule layout | reason=compiler code must be organized by model responsibility, with top-level files limited to flakes, tests, entrypoints, and thin imports into s88-style responsibility folders; new policy or behavior must not be added as root-level blobs.
- state=required | target=no oversized implementation files | reason=Nix implementation files over 200 LOC must be split by concrete responsibility unless they are flake/test wiring or explicitly documented as a temporary regression with a split target.
