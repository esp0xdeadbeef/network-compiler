#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <config.nix>" >&2
  exit 2
fi

CONFIG_PATH="$1"

cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

if command -v realpath >/dev/null 2>&1; then
  CONFIG_ABS="$(realpath "$CONFIG_PATH")"
else
  case "$CONFIG_PATH" in
    /*) CONFIG_ABS="$CONFIG_PATH" ;;
    *)  CONFIG_ABS="$(pwd)/$CONFIG_PATH" ;;
  esac
fi

nix eval --impure --json --expr "
  let
    flake = builtins.getFlake (toString ./.);
    lib = flake.lib;

    main = import ./lib/main.nix { nix = flake; };
    net = main.fromFile (builtins.toPath \"${CONFIG_ABS}\");
  in
    net.sites
"

