{
  lib,
  coreNames,
  coreUplinks,
  helpers,
  services,
}:

let
  inherit (helpers)
    candidateId
    containsLiteralFields
    identity
    sortRecords
    sortedUnique
    warning
    ;
  warningsMod = import ./warnings.nix {
    inherit lib warning candidateId services;
  };
in
{
  evaluate =
    binding:
    let
      requester = identity (binding.requesterScope or null);
      upstream = binding.upstreamResolver or null;
      upstreamIsAttrs = builtins.isAttrs upstream;
      upstreamKind = if upstreamIsAttrs then upstream.kind or null else null;
      serviceName = if upstreamIsAttrs then upstream.name or "<missing>" else "<missing>";
      requestedNode = if upstreamIsAttrs then upstream.node or null else null;
      candidates = services.candidatesByName.${toString serviceName} or [ ];
      candidateIds = map candidateId candidates;
      selected = if builtins.length candidates == 1 then builtins.head candidates else null;
      selectedNode = if selected == null then null else selected.providerNode or null;
      literal =
        (upstream != null && !upstreamIsAttrs)
        || containsLiteralFields upstream
        || (
          upstreamIsAttrs
          && builtins.elem upstreamKind [
            "address"
            "host"
            "literal"
          ]
        );
      missing = upstream == null;
      ambiguous = builtins.length candidates > 1;
      invalid =
        !missing
        && !literal
        && (
          upstreamKind != "service"
          || builtins.length candidates == 0
          || selectedNode == null
          || !builtins.elem selectedNode coreNames
          || (requestedNode != null && requestedNode != selectedNode)
        );
      families =
        if builtins.isList (binding.allowedAddressFamilies or null) then
          sortedUnique binding.allowedAddressFamilies
        else
          [ ];
      invalidFamilies = lib.filter (
        family:
        !builtins.elem family [
          "ipv4"
          "ipv6"
        ]
      ) families;
      egress = binding.egressSurface or null;

      egressNamed =
        if !(builtins.isAttrs egress) then
          [ ]
        else if builtins.isList (egress.uplinks or null) then
          sortedUnique egress.uplinks
        else if builtins.isString (egress.scope or null) && egress.scope != "" then
          let
            scopeUplinks = map (u: u.name) (coreUplinks.${egress.scope} or [ ]);
            coreNamesOf = coreUplinks.${egress.scope} or null;
          in
          sortedUnique (if scopeUplinks != [ ] then scopeUplinks else [ egress.scope ])
        else if builtins.isString (egress.name or null) && egress.name != "" then
          [ egress.name ]
        else
          [ ];

      egressUplinks = egressNamed;
      selectedCoreUplinks =
        if selectedNode == null then
          [ ]
        else
          map (uplink: uplink.name) (coreUplinks.${selectedNode} or [ ]);

      missingEgress = egressUplinks == [ ];
      ambiguousEgress = builtins.length egressUplinks > 1;
      invalidEgress = lib.filter (uplink: !(builtins.elem uplink selectedCoreUplinks)) egressUplinks;
      unstableEgress = (binding.egressSelectionMode or null) == "first-listed";
      fallbackInvalid = (binding.directPublicFallback or false) != false;
      warnings = warningsMod.collect {
        inherit
          requester
          serviceName
          requestedNode
          selectedNode
          candidateIds
          families
          invalidFamilies
          egressUplinks
          selectedCoreUplinks
          invalidEgress
          missing
          literal
          ambiguous
          invalid
          missingEgress
          ambiguousEgress
          unstableEgress
          fallbackInvalid
          ;
      };
      active =
        warnings == [ ]
        &&
          families == [
            "ipv4"
            "ipv6"
          ]
        && invalidFamilies == [ ];
      normalized = {
        requesterScope = binding.requesterScope;
        advertisedResolver = binding.advertisedResolver or binding.requesterScope;
        resolverSource = binding.resolverSource or "local-recursive";
        upstreamResolver = {
          kind = "service";
          name = serviceName;
          node = selectedNode;
        };

        egressSurface = {
          kind = "external";
          uplinks = egressUplinks;
        };
        returnBehavior = binding.returnBehavior or "symmetric";
        allowedAddressFamilies = families;
        directPublicFallback = false;
      };
    in
    {
      inherit warnings active normalized;
    };
}
