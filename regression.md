# network-compiler Regression Notes

This file records current policy exceptions only. Keep entries exact and
current; do not use it as a session log.

## Nix File LOC States

The file-size guard requires every tracked Nix file over the soft limit to have
a current state and reason. Files at or above the hard limit fail immediately
and must be split before tests can pass.

<!-- nix-file-loc:start -->
235 flake.nix | state=watch | reason=contains flake inputs plus app/check builders; next split is moving app builders under a flake/ module
<!-- nix-file-loc:end -->
