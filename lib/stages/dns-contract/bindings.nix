{
  lib,
  recursiveRaw,
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
  raw = if builtins.isList (recursiveRaw.bindings or null) then recursiveRaw.bindings else [ ];

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
      egressUplinks =
        if builtins.isAttrs egress && builtins.isList (egress.uplinks or null) then
          sortedUnique egress.uplinks
        else
          [ ];
      selectedCoreUplinks =
        if selectedNode == null then
          [ ]
        else
          map (uplink: uplink.name) (coreUplinks.${selectedNode} or [ ]);
      missingEgress = egressUplinks == [ ];
      ambiguousEgress = builtins.length egressUplinks > 1;
      invalidEgress = lib.filter (uplink: !builtins.elem uplink selectedCoreUplinks) egressUplinks;
      unstableEgress = (binding.egressSelectionMode or null) == "first-listed";
      fallbackInvalid = (binding.directPublicFallback or false) != false;
      warnings =
        lib.optional missing (warning {
          code = "DNS_CORE_BINDING_MISSING";
          inherit requester;
          candidateIds = map candidateId services.raw;
        })
        ++ lib.optional literal (warning {
          code = "DNS_CORE_BINDING_LITERAL";
          inherit requester;
          resolverService = serviceName;
          candidateIds = candidateIds;
          context = "upstream-resolver";
        })
        ++ lib.optional ambiguous (warning {
          code = "DNS_CORE_BINDING_AMBIGUOUS";
          inherit requester;
          resolverService = serviceName;
          candidateIds = candidateIds;
        })
        ++ lib.optional invalid (warning {
          code = "DNS_CORE_BINDING_INVALID";
          inherit requester;
          resolverService = serviceName;
          resolverNode = requestedNode;
          candidateIds = candidateIds;
        })
        ++ map (
          family:
          warning {
            code = "DNS_CORE_FAMILY_INCOMPLETE";
            inherit requester family;
            resolverService = serviceName;
            resolverNode = selectedNode;
            candidateIds = candidateIds;
          }
        ) invalidFamilies
        ++ lib.optional missingEgress (warning {
          code = "DNS_EGRESS_SELECTION_MISSING";
          inherit requester;
          resolverService = serviceName;
          resolverNode = selectedNode;
          candidateIds = selectedCoreUplinks;
        })
        ++ lib.optional ambiguousEgress (warning {
          code = "DNS_EGRESS_SELECTION_AMBIGUOUS";
          inherit requester;
          resolverService = serviceName;
          resolverNode = selectedNode;
          candidateIds = egressUplinks;
        })
        ++ lib.optional (invalidEgress != [ ]) (warning {
          code = "DNS_EGRESS_SELECTION_MISSING";
          inherit requester;
          resolverService = serviceName;
          resolverNode = selectedNode;
          candidateIds = invalidEgress;
          context = "unknown-provider-uplink";
        })
        ++ lib.optional unstableEgress (warning {
          code = "DNS_EGRESS_SELECTION_UNSTABLE";
          inherit requester;
          resolverService = serviceName;
          resolverNode = selectedNode;
          candidateIds = selectedCoreUplinks;
        })
        ++ lib.optional fallbackInvalid (warning {
          code = "DNS_RECURSION_MODE_INVALID";
          inherit requester;
          resolverService = serviceName;
          resolverNode = selectedNode;
          candidateIds = candidateIds;
          context = "direct-public-fallback";
        });
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
        resolverPath = binding.resolverPath or [ ];
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

  evaluations = map evaluate raw;
  missingBindingWarnings =
    if raw != [ ] || services.normalized == [ ] then
      [ ]
    else
      map (
        service:
        warning {
          code = "DNS_CORE_BINDING_MISSING";
          requester = "unbound-requester";
          resolverService = service.name;
          resolverNode = service.providerNode;
          candidateIds = map candidateId services.raw;
          context = "named-core-binding";
        }
      ) services.normalized;
in
{
  warnings = missingBindingWarnings ++ lib.concatMap (entry: entry.warnings) evaluations;
  normalized = sortRecords (
    map (entry: entry.normalized) (lib.filter (entry: entry.active) evaluations)
  );
}
