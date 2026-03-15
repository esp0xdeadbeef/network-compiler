#nix run path:.#compile -- ../network-labs/examples/single-wan/intent.nix
#nix run path:.#compile -- git@github.com:esp0xdeadbeef/network-labs.git/examples/single-wan/intent.nix
example_repo=$(nix eval --raw --impure --expr 'builtins.fetchGit { url = "git@github.com:esp0xdeadbeef/network-labs.git";}')
nix run .#compile -- $example_repo/examples/single-wan/intent.nix
