{ lib }:

let
  util = import ../correctness/util.nix { inherit lib; };
  inherit (util) ensure;

  has = attr: attrs: builtins.isAttrs attrs && builtins.hasAttr attr attrs;

  isManagementDeniedPath =
    entry:
    let
      to = entry.to or { };
      kind = entry.kind or null;
      reason = entry.reason or "";
      negativeProbe = entry.negativeProbe or "";
    in
    kind == "media-to-management"
    || kind == "management-denied"
    || (to.kind or null) == "management"
    || (to.name or null) == "management"
    || lib.hasInfix "management" reason
    || lib.hasInfix "management" negativeProbe;
in
siteKey: serviceName: policy:
let
  isMediaReceiver = (policy.serviceClass or "") == "media-receiver";
  managementDenied = has "management" policy && ((policy.management.allowed or false) == false);
  deniedPaths = policy.deniedPaths or [ ];
  hasManagementDeniedPath = builtins.any isManagementDeniedPath deniedPaths;

  requireManagementAccessPolicy =
    ensure (!(has "management" policy && policy.management.allowed or false == true && !(has "managementAccessPolicy" policy))) {
      code = "MANAGEMENT_INFERRED_FROM_PAYLOAD";
      site = siteKey;
      path = [
        "communicationContract"
        "services"
        serviceName
        "servicePolicy"
        "management"
      ];
      message = "service '${serviceName}' management.allowed is true but no explicit managementAccessPolicy record; management reachability must be explicitly modeled, not inferred from discovery, payload, or reverse initiation";
      hints = [
        "Add a managementAccessPolicy field to the service policy to explicitly authorize management access."
      ];
    };

  requireManagementDeniedPath =
    ensure (!(isMediaReceiver && managementDenied && !hasManagementDeniedPath)) {
      code = "MISSING_DENIED_PATH_DATA";
      site = siteKey;
      path = [
        "communicationContract"
        "services"
        serviceName
        "servicePolicy"
        "deniedPaths"
      ];
      message = "service '${serviceName}' management reachability is denied but denied-path data for the media-to-management path is absent";
      hints = [
        "Add a deniedPath record with kind = \"media-to-management\" or a management target for the media service."
      ];
    };
in
builtins.deepSeq
  [ requireManagementAccessPolicy requireManagementDeniedPath ]
  true
