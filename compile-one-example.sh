#nix run path:.#compile -- ../network-labs/examples/single-wan/intent.nix
#nix run path:.#compile -- git@github.com:esp0xdeadbeef/network-labs.git/examples/single-wan/intent.nix
#example_repo=$(nix eval --raw --impure --expr 'builtins.fetchGit { url = "git@github.com:esp0xdeadbeef/network-labs.git";}')
example_repo=$(nix flake prefetch github:esp0xdeadbeef/network-labs --json | jq -r .storePath)
#example_repo=$(echo /home/deadbeef/github/network-labs)
#nix run .#compile -- $example_repo/examples/multi-wan/intent.nix
nix run .#compile -- $example_repo/examples/multi-wan/intent.nix
