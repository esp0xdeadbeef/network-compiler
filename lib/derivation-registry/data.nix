# FS-172-HDS-010-SDS-010: the derivation-rule registry contents.
#
# These entries reference the Derivation-Rule Registry Map in
# FS-172-HDS-010-SDS-010 by rule identity. The map owns each rule's inputs and
# output; this file names the identities so a fault can cite them.

{
  # Rule identities from the SDS map. A reference, not a copy: the identity is
  # named so a fault can cite it, while the rule's inputs and output stay owned by
  # the SDS. The duplicate-rule-identity refusal below is what keeps this honest —
  # the same identity cannot be registered twice.
  ruleIdentities = [
    "DRV-FABRIC-ADJ"
    "DRV-DNS-RESOLVER-PATH"
    "DRV-DNS-RESOLVER-EGRESS"
    "DRV-SERVICE-PERMISSION-SHAPE"
    "DRV-PREFIX-EXIT-BINDING"
  ];

  # Each entry carries the four facts the SMS names: identity, determining
  # declared facts, owning deriving layer, and the derived fact it produces.
  defaultEntries = [
    {
      ruleId = "DRV-FABRIC-ADJ";
      derivedFact = "fabricSelectorRoles";
      determiningFacts = [
        "scopeOffers"
        "scopeSelects"
        "permission"
      ];
      owningLayer = "network-control-plane-model: fabric";
    }
    {
      ruleId = "DRV-DNS-RESOLVER-PATH";
      derivedFact = "resolverPath";
      determiningFacts = [
        "requesterScope"
        "advertisedResolver"
        "resolverSource"
        "followSource"
        "exit"
        "allowedAddressFamily"
      ];
      owningLayer = "network-compiler: traffic paths";
    }
    {
      ruleId = "DRV-DNS-RESOLVER-EGRESS";
      derivedFact = "resolverEgressPermission";
      determiningFacts = [
        "dnsRelationship"
        "egressSelection"
        "dnsPolicy"
      ];
      owningLayer = "network-control-plane-model: dns contract";
    }
    {
      ruleId = "DRV-SERVICE-PERMISSION-SHAPE";
      derivedFact = "permissionShape";
      determiningFacts = [
        "serviceDeclaration"
        "trafficType"
      ];
      owningLayer = "network-compiler: relations";
    }
    {
      ruleId = "DRV-PREFIX-EXIT-BINDING";
      derivedFact = "prefixExitBinding";
      determiningFacts = [
        "prefixAuthority"
        "selectedExit"
      ];
      owningLayer = "network-control-plane-model: uplinks";
    }
  ];
}
