#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT"

nix run --no-write-lock-file .#flatten   examples/single-wan/inputs.nix | tee /tmp/inputs-flatten.json
nix run .#normalize /tmp/inputs-flatten.json | tee /tmp/inputs-normalized.json
nix run .#invPre   /tmp/inputs-normalized.json | tee /tmp/inputs-invPre.json
nix run .#compile  /tmp/inputs-invPre.json | tee /tmp/inputs-compile.json
nix run .#invPost  /tmp/inputs-compile.json | tee /tmp/inputs-invPost.json
nix run .#check    /tmp/inputs-invPost.json

nix run path:"$REPO_ROOT"#debug examples/single-wan/inputs.nix
