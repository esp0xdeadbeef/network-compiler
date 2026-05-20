{ lib }:

serviceIndex: serviceNames:
map
  (
    name:
    let
      svc = serviceIndex.${name};
    in
    {
      name = svc.name;
      trafficType = svc.trafficType or "any";
    }
  )
  (lib.sort builtins.lessThan serviceNames)
