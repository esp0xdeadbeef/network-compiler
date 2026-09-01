{ lib }:

let
  util = import ../../correctness/util.nix { inherit lib; };
  policyC = import ../../correctness/policy.nix { inherit lib; };
  topoC = import ../../correctness/topology.nix { inherit lib; };
  addressSafety = import ../../address-safety { inherit lib; };
  normalizeUplinksForNode = import ../normalize-uplinks.nix { inherit lib; };
  normalizeTransportOverlays = import ../normalize-overlays.nix { inherit lib; };
  buildOverlayAttachments = import ../overlay-attachments.nix { inherit lib; };
  validateOverlayModel = import ../validate-overlay-model.nix { inherit lib; };
  buildTrafficPaths = import ../traffic-paths.nix { inherit lib; };
  validateNoLegacyExternalPolicy = import ../validate-no-legacy-external.nix { inherit lib; };
  validateIntentSourceBoundary = import ../validate-intent-source-boundary.nix { inherit lib; };
  platformIndependence = import ../validate-platform-independence.nix { inherit lib; };
  validateServiceProviders = import ../validate-service-providers.nix { inherit lib; };
  buildCompiledServices = import ../compiled-services.nix { inherit lib; };
  buildIsolationDecisions = import ../isolation-decisions.nix { inherit lib; };
  buildAccessSpaceDiscovery = import ../access-space-discovery { inherit lib; };
  sourceAudit = import ../source-audit.nix { inherit lib; };
  buildDnsContract = import ../dns-contract { inherit lib; };
  buildCoreUplinks = import ../core-uplinks.nix {
    inherit lib normalizeUplinksForNode;
    inherit (util) ensure;
  };
  inherit (util) assertUnique ensure;
  inherit (policyC)
    buildTrafficTypeIndex
    buildServiceIndex
    normalizeRelationWithProvenance
    sortRelations
    ensureNoConflictingRelations
    ensureHasExternalAllow
    ;

  fabricMod = import ./fabric.nix {
    inherit
      lib
      topoC
      addressSafety
      normalizeUplinksForNode
      normalizeTransportOverlays
      buildCoreUplinks
      ;
  };
  contractsMod = import ./contracts.nix {
    inherit
      lib
      ensure
      assertUnique
      buildDnsContract
      buildTrafficTypeIndex
      buildServiceIndex
      validateNoLegacyExternalPolicy
      validateIntentSourceBoundary
      platformIndependence
      ;
  };
  relationsMod = import ./relations.nix {
    inherit
      lib
      assertUnique
      policyC
      validateOverlayModel
      validateServiceProviders
      buildOverlayAttachments
      buildTrafficPaths
      buildCompiledServices
      buildIsolationDecisions
      buildAccessSpaceDiscovery
      ;
  };
  outputMod = import ./output.nix { inherit lib; };
in
siteKey: declared: semantic:
let
  fabric = fabricMod.prepare siteKey declared semantic;
  contracts = contractsMod.prepare siteKey declared semantic fabric;
  relations = relationsMod.prepare siteKey declared semantic fabric contracts;
  validations = fabric.validations // contracts.validations // relations.validations;
in
outputMod.build {
  inherit
    sourceAudit
    siteKey
    platformIndependence
    declared
    semantic
    ;
  inherit (fabric)
    topo
    normalizedTopologyNodes
    overlayAddressPools
    ;
  inherit (contracts)
    tenants
    dns
    ;
  inherit (relations)
    normalizedRelations
    overlayAttachments
    trafficPaths
    compiledServices
    isolationModel
    accessSpaceDiscovery
    ;
  inherit validations;
}
