{ lib }:

# FS-610-HDS-010-SDS-010-SMS-040: broad discovery flooding denial
# Scans discovery boundary contracts and rejects broad multicast flooding
# and reverse discovery without explicit modeled relationships.
siteKey: contract:
let
  util = import ./correctness/util.nix { inherit lib; };
  inherit (util) ensure;

  has = attr: attrs: builtins.isAttrs attrs && builtins.hasAttr attr attrs;

  # BROAD FLOODING DENIAL
  # Reject relayOrProxyBoundary values that indicate unscoped multicast flooding.
  relayOrProxyBoundary = contract.relayOrProxyBoundary or "";
  isMulticastFlood = builtins.isString relayOrProxyBoundary
    && (lib.hasPrefix "multicast-flood" relayOrProxyBoundary || lib.hasInfix "-multicast-flood-" relayOrProxyBoundary
        || relayOrProxyBoundary == "multicast-flood");

  hasScopeRestriction =
    has "scope" contract && contract.scope != "*" && contract.scope != null;

  _broadFlooding =
    if isMulticastFlood && !hasScopeRestriction then
      ensure false {
        code = "BROAD_FLOODING_DENIED";
        site = siteKey;
        path = [
          "accessSpaceDiscovery"
          "exported"
          (contract.requesterScope or "unknown")
          (contract.service or "unknown")
        ];
        message = "broad multicast flooding denied: relayOrProxyBoundary '${relayOrProxyBoundary}'"
          + " indicates unscoped multicast flooding without explicit modeled relationship";
        hints = [
          "Model explicit relay or proxy relationships with named requester and responder scopes."
          "Multicast flooding to all scopes (scope: '*') is denied unless a modeled relationship permits it."
          "Remove relayMode: 'multicast-flood' or add explicit scope restriction and modeled relationship record."
        ];
      }
    else
      true;

  # REVERSE DISCOVERY DENIAL
  # Reject reverse discovery without explicit reverse-path relationship.
  reverseDiscovery = contract.reverseDiscovery or contract.reverse or false;
  hasReversePathRelationship =
    (has "reversePathRelationship" contract && contract.reversePathRelationship != null && contract.reversePathRelationship != false)
    || (has "reversePath" contract && contract.reversePath != null && contract.reversePath != false)
    || (has "modeledRelationship" contract
        && builtins.isAttrs contract.modeledRelationship
        && (contract.modeledRelationship.reverse or false) == true);

  _reverseDiscovery =
    if reverseDiscovery == true && !hasReversePathRelationship then
      ensure false {
        code = "REVERSE_DISCOVERY_DENIED";
        site = siteKey;
        path = [
          "accessSpaceDiscovery"
          "exported"
          (contract.requesterScope or "unknown")
          (contract.service or "unknown")
        ];
        message = "reverse discovery denied: reverseDiscovery is set without"
          + " an explicit reverse-path relationship record";
        hints = [
          "Model reverse discovery paths explicitly as separate authorization records."
          "Reverse discovery is not self-authorizing; a reversePathRelationship record is required."
          "Remove the reverseDiscovery flag or add a modeledRelationship with reverse authorization."
        ];
      }
    else
      true;
in
builtins.deepSeq [ _broadFlooding _reverseDiscovery ] true
