{ lib }:

compiled:

let
  sites = if compiled ? sites then compiled.sites else compiled;

  parseSegmentRef =
    s:
    let
      m = builtins.match "([^:]+):(.*)" s;
    in
    if m == null then
      {
        kind = "segment";
        name = s;
      }
    else
      let
        ns = builtins.elemAt m 0;
        name = builtins.elemAt m 1;
      in
      if ns == "tenants" then
        {
          kind = "tenant";
          inherit name;
        }
      else if ns == "services" then
        {
          kind = "service";
          inherit name;
        }
      else
        {
          kind = "segment";
          namespace = ns;
          inherit name;
        };

  unitRef = name: {
    kind = "unit";
    inherit name;
  };

  realizeSite =
    siteKey: site:
    let
      model = if site ? model then site.model else site;

      attachments0 = model.attachment or [ ];

      attachmentsByUnit =
        let
          units = lib.unique (map (a: a.unit) attachments0);
        in
        map (u: {
          unit = unitRef u;
          attachments = map (a: {
            segment = parseSegmentRef a.segment;
          }) (lib.filter (a: a.unit == u) attachments0);
        }) units;

      ordering0 = model.transit.ordering or [ ];

      edges = map (
        pair:
        let
          from = builtins.elemAt pair 0;
          to = builtins.elemAt pair 1;
        in
        {
          from = unitRef from;
          to = unitRef to;
        }
      ) ordering0;

      tenants = (model.domains.tenants or [ ]);

      ownedPrefixes = map (t: {
        tenant = {
          kind = "tenant";
          name = t.name;
        };
        prefixes = (lib.optional (t ? ipv4) t.ipv4) ++ (lib.optional (t ? ipv6) t.ipv6);
      }) tenants;

      communicationContract = model.communicationContract or { };

    in
    {
      site = {
        id = siteKey;
        enterprise = model.enterprise or null;
      };

      solverOutput = {
        units = attachmentsByUnit;
        transit = {
          edges = edges;
        };
        ownedPrefixes = ownedPrefixes;
        communicationContract = communicationContract;
      };
    };

in
lib.mapAttrs realizeSite sites
