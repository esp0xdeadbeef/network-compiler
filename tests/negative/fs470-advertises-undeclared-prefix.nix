let
  base = import ../fixtures/fs483-liveness-satisfiable.nix;
in
base
// {
  goodsite = base.goodsite // {
    topology = base.goodsite.topology // {
      nodes = base.goodsite.topology.nodes // {
        core-a = base.goodsite.topology.nodes.core-a // {

          advertises = [
            "192.0.2.0/24"
          ];
        };
      };
    };
  };
}
