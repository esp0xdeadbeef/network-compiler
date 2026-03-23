let
  lib = import <nixpkgs/lib>;
  compiler = import ../../lib { inherit lib; };

  exampleRepo =
    let
      env = builtins.getEnv "NETWORK_LABS_REPO";
    in
    if env != "" then
      env
    else
      throw "NETWORK_LABS_REPO must point to a checked-out or prefetched network-labs repo";

  candidates = [
    "${exampleRepo}/multi-enterprise/intent.nix"
    "${exampleRepo}/examples/multi-enterprise/intent.nix"
    "${exampleRepo}/multi-enterprise/inputs.nix"
    "${exampleRepo}/examples/multi-enterprise/inputs.nix"
  ];

  existing = builtins.filter builtins.pathExists candidates;

  inputPath =
    if existing == [ ] then
      throw "multi-enterprise example not found in NETWORK_LABS_REPO"
    else
      builtins.head existing;

  input = import inputPath;
in
compiler.compile input
