{ }:

let
  singleWan = import ../inputs/single-wan.nix;
  multiWan = import ./multi-wan.nix;
  multiEnterprise = import ./multi-enterprise.nix;
  priorityStability = import ./priority-stability.nix;
in
{
  single-wan = singleWan;
  multi-wan = multiWan;
  multi-enterprise = multiEnterprise;
  priority-stability = priorityStability;
}
