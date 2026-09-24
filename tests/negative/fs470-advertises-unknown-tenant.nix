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
            {
              kind = "tenant";
              name = "no-such-tenant";
            }
          ];
        };
      };
    };
  };
}
