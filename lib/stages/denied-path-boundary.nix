{ lib }:

let
  util = import ../correctness/util.nix { inherit lib; };
  inherit (util) ensure;

  has = attr: attrs: builtins.isAttrs attrs && builtins.hasAttr attr attrs;
in
siteKey: serviceName: policy:
ensure (!(builtins.length (policy.deniedPaths or [ ]) == 0)) {
  code = "MISSING_DENIED_PATH_DATA";
  site = siteKey;
  path = [
    "communicationContract"
    "services"
    serviceName
    "servicePolicy"
    "deniedPaths"
  ];
  message = "service '${serviceName}' deniedPaths is empty; shared services must declare explicit denied-path data for guest, media, untrusted, and unrelated scopes";
  hints = [
    "Add at least one deniedPath record naming the denied scope (e.g. guest, media) with a reason and negative probe."
  ];
}
