#!/usr/bin/env bash
#example_repo=$(nix eval --raw --impure --expr 'builtins.fetchGit { url = "git@github.com:esp0xdeadbeef/network-labs.git";}')
example_repo=$(nix flake prefetch github:esp0xdeadbeef/network-labs --json | jq -r .storePath)

find $example_repo -name 'intent.nix' -print0 |
  while IFS= read -r -d '' f; do
    echo ""
    echo "=== $f ==="
    nix run path:.#compile -- "$f" | jq -c
  done
