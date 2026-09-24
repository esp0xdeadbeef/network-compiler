let
  base = import ./fs483-liveness-satisfiable.nix;
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
              name = "mgmt";
            }
            "10.20.10.0/24"
          ];
        };
      };
    };
  };
}
