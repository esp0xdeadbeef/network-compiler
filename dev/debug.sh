#!/usr/bin/env bash
set -euo pipefail

FILE="$1"
QUERY="${2:-c: c}"
QUERY="${2:-c: builtins.trace (builtins.toJSON c) c}"


if [[ -d "$FILE" ]]; then
  FILE="$FILE/default.nix"
fi

nix eval --impure --json --expr "
let
  flake = builtins.getFlake (toString ./.);
  lib = flake.lib;
  eval = import \"\${flake}/dev/debug.nix\" { inherit lib; };

  compiled = eval { topology = import ./$FILE; };
  f = $QUERY;
in
  f compiled
" | jq

