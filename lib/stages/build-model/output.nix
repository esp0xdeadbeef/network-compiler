{ lib }:

{

  build =
    {
      sourceAudit,
      siteKey,
      platformIndependence,
      declared,
      semantic,
      topo,
      tenants,
      compiledServices,
      isolationModel,
      accessSpaceDiscovery,
      normalizedRelations,
      overlayAttachments,
      overlayAddressPools,
      overlays,
      trafficPaths,
      normalizedTopologyNodes,
      dns,
      communicationContractDeclared,
      validations,
    }:
    let
      poolCapacity = import ../../allocators/pool-capacity.nix { inherit lib; };
      semanticAddressPools = semantic.addressPools or { };

      _poolCapacity = poolCapacity.validateSite {
        siteKey = siteKey;
        transitLinks = (semantic.transit or { }).links or [ ];
        nodeCount = builtins.length (builtins.attrNames (topo.nodes or { }));
        addressPools = semanticAddressPools;
      };
      model0 = {
        tenants = tenants;
        services = compiledServices;
        consumedInterfaces = isolationModel.consumedInterfaces;
        isolationDecisions = isolationModel.isolationDecisions;
        accessSpaceDiscovery = accessSpaceDiscovery;
        ipv6 = semantic.ipv6 or { };
        relations = normalizedRelations;

        communicationContract = {
          trafficTypes = communicationContractDeclared.trafficTypes or [ ];
          services = communicationContractDeclared.services or [ ];
          relations = normalizedRelations;
        };
        overlayAttachments = overlayAttachments;
        overlayAddressPools = overlayAddressPools;
        transport = {
          overlays = overlays;
        };
        addressPools = builtins.seq _poolCapacity semanticAddressPools;
        trafficPaths = trafficPaths;
        hostNatIngress = topo.hostNatIngress or { };
        prefixAuthority = declared.prefixAuthority or { };
        transit = semantic.transit or { };
        providerHandoffs = semantic.providerHandoffs or [ ];
        hostManagement = declared.hostManagement or null;
        # Routing-owned index of modeled endpoints and prefixes. The forwarding
        # model resolves provider tenants, service-route scopes, and NAT source
        # prefixes from this index, and the control-plane model consumes the
        # same normalized record. It is the compiler-resolved site ownership and
        # is a distinct key from FS-390's `destinationOwnership` classification
        # record below.
        ownership = declared.ownership or { };
        # FS-390: emit the modeled endpoint ownership as a destination-ownership
        # record (separate from routing's site.ownership index) so the
        # forwarding model can classify locally-owned-routed and provider-owned
        # public IPv4 destinations before route selection.
        destinationOwnership = {
          endpoints = (declared.ownership or { }).endpoints or [ ];
        };
        topology = {
          nodes = normalizedTopologyNodes;
          links = topo.links or [ ];
        };
        inherit dns;
      };
      model = sourceAudit.attach siteKey model0;
      platformIndependentOutput = platformIndependence.validateOutput siteKey model;
      forced = builtins.deepSeq (
        validations
        // {
          platformIndependentOutput = platformIndependentOutput;
          tenants = model0.tenants;
          services = model0.services;
          accessSpaceDiscovery = model0.accessSpaceDiscovery;
          ipv6 = model0.ipv6;
          relations = model0.relations;
          communicationContract = model0.communicationContract;
          overlayAttachments = model0.overlayAttachments;
          overlayAddressPools = model0.overlayAddressPools;
          transport = model0.transport;
          addressPools = model0.addressPools;
          trafficPaths = model0.trafficPaths;
          hostNatIngress = model0.hostNatIngress;
          sourceAudit = model.sourceAudit;
          dns = model0.dns;
        }
      ) model;
    in
    builtins.seq forced model;
}
