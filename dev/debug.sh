# ./dev/debug.sh
#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <config.nix> [site-name]" >&2
  exit 2
fi

CONFIG_PATH="$1"
SITE_NAME="${2:-}"

cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

if command -v realpath >/dev/null 2>&1; then
  CONFIG_ABS="$(realpath "$CONFIG_PATH")"
else
  case "$CONFIG_PATH" in
    /*) CONFIG_ABS="$CONFIG_PATH" ;;
    *)  CONFIG_ABS="$(pwd)/$CONFIG_PATH" ;;
  esac
fi

if [[ -n "$SITE_NAME" ]]; then
  nix eval --impure --json --expr "
    let
      flake = builtins.getFlake (toString ./.);
      main = import ./lib/main.nix { nix = flake; };
      net = main.fromFile (builtins.toPath \"${CONFIG_ABS}\");
    in
      net.sites.\"${SITE_NAME}\"
  "
else
  nix eval --impure --json --expr "
    let
      flake = builtins.getFlake (toString ./.);
      main = import ./lib/main.nix { nix = flake; };
      net = main.fromFile (builtins.toPath \"${CONFIG_ABS}\");
    in
      net.sites
  "
fi

