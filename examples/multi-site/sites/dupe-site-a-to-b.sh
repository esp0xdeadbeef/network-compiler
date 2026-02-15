#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

sed -e 's/site-a/site-b/g' \
    -e 's/10\.20/10.30/g' \
    -e 's/fd42:dead:beef:a/fd42:dead:beef:b/g' \
    -e 's/"a-router-/"b-router-/g' \
    ./site-a.nix > ./site-b.nix

