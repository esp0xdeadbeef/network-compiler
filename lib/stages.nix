{ lib }:

let

  flattenSites = import ./flatten-sites.nix { inherit lib; };
  normalizeSite = import ./normalize/from-user-input.nix { inherit lib; };

  mkPortForwardRelations =
    declared:
    let
      nodes = declared.nodes or { };

      coreNames = lib.filter (n: (nodes.${n}.role or null) == "core") (builtins.attrNames nodes);

      forwards = lib.concatMap (
        coreName:
        let
          core = nodes.${coreName};
          isp = core.isp or { };
          fps = isp.forwardPorts or [ ];
        in
        map (fp: {
          from = {
            external = "default";
          };
          to = if fp ? target then { service = fp.target; } else { };
          action = "allow";
          proto = [ "tcp/${toString fp.port}" ];
        }) fps
      ) coreNames;
    in
    forwards;

  buildModel =
    siteKey: declared: semantic:
    let
      processCell = declared.processCell or { };
      policyIntent = processCell.policyIntent or [ ];

      tenants = semantic.segments.tenants or [ ];

      trafficClasses = lib.unique (
        lib.concatMap (rule: if rule ? proto then rule.proto else [ "any" ]) policyIntent
      );

      baseAllowedRelations = map (rule: {
        from = rule.from or { };
        to = rule.to or { };
        action = rule.action or "deny";
        proto = rule.proto or [ "any" ];
      }) policyIntent;

      portForwardRelations = mkPortForwardRelations declared;

      allowedRelations = baseAllowedRelations ++ portForwardRelations;

      transformations =
        let
          t = processCell.transformations or { };
        in
        lib.filterAttrs (_: v: v != [ ]) {
          dnat = t.dnat or [ ];
          snat = t.snat or [ ];
        };

      enforcement =
        let
          auth = processCell.authority or { };
          tf = processCell.transitForwarder or { };
        in
        lib.filterAttrs (_: v: v != { } && v != null) {
          requirePolicyEngine = true;
          authorityRoles = auth;
          transitForwarder = tf;
        };

      communicationContract = {
        trafficClasses = trafficClasses;
        allowedRelations = allowedRelations;
      }
      // lib.optionalAttrs (transformations != { }) { inherit transformations; }
      // lib.optionalAttrs (enforcement != { }) { inherit enforcement; };

    in
    {
      id = siteKey;
      enterprise = semantic.enterprise or "default";

      domains = {
        tenants = tenants;
      };

      attachment = semantic.attachments or [ ];

      transit = {
        ordering = semantic.transit.links or [ ];
        addressAuthority = semantic.transit.pool or null;
      };

      inherit communicationContract;
    };

  compileSite =
    siteKey: declared:
    let
      semantic = normalizeSite declared;
      model = buildModel siteKey declared semantic;
    in
    model;

in
{

  run =
    inputs:
    let
      sites = flattenSites inputs;
      compiled = lib.mapAttrs compileSite sites;
    in
    {
      sites = compiled;
    };
}
