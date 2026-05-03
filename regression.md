# network-compiler Regression Notes

This file records current policy exceptions only. Keep entries exact and
current; do not use it as a session log.

## Nix File LOC States

The file-size guard requires every tracked Nix file over the soft limit to have
a current state and reason. Files at or above the hard limit fail immediately
and must be split before tests can pass.

<!-- nix-file-loc:start -->
235 flake.nix | state=watch | reason=mkEvalApp and checkDrv still define the compile/debug/check app contract around self.outPath; split into flake/apps.nix when app names and generated shell behavior can stay identical
<!-- nix-file-loc:end -->
