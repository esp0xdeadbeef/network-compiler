# FS-525 / FS-540: deterministic, privacy-safe warning records for a DNS core
# binding evaluation. Split out of evaluate.nix so the binding evaluation module
# stays under the tracked LOC soft limit.
{
  lib,
  warning,
  candidateId,
  services,
}:

let
  inherit (services) candidatesByName raw;
in
{
  # Build the ordered warning set for one evaluated binding.
  #
  # Inputs are the classified booleans/collections computed by the evaluation
  # module, plus the identities the warnings name. Warnings carry modeled
  # identifiers only (requester, service, node, candidate ids); no addresses.
  collect =
    {
      requester,
      serviceName,
      requestedNode,
      selectedNode,
      candidateIds,
      families,
      invalidFamilies,
      egressUplinks,
      selectedCoreUplinks,
      invalidEgress,
      missing,
      literal,
      ambiguous,
      invalid,
      missingEgress,
      ambiguousEgress,
      unstableEgress,
      fallbackInvalid,
      directPublicFallback ? false,
    }:
    let
      allCandidateIds = map candidateId raw;
    in
    lib.optional missing (warning {
      code = "DNS_CORE_BINDING_MISSING";
      inherit requester;
      candidateIds = allCandidateIds;
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
}
