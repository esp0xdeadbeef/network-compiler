{ }:

let
  singleWan = import ../inputs/single-wan.nix;

in
{
  single-wan = singleWan;

  multi-wan = singleWan;

  multi-enterprise = singleWan;

  priority-stability = singleWan;
}
