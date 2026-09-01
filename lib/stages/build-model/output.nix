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
      trafficPaths,
      normalizedTopologyNodes,
      dns,
      validations,
    }:
    let
      model0 = {
        tenants = tenants;
        services = compiledServices;
        consumedInterfaces = isolationModel.consumedInterfaces;
        isolationDecisions = isolationModel.isolationDecisions;
        accessSpaceDiscovery = accessSpaceDiscovery;
        ipv6 = semantic.ipv6 or { };
        relations = normalizedRelations;
        overlayAttachments = overlayAttachments;
        overlayAddressPools = overlayAddressPools;
        trafficPaths = trafficPaths;
        hostNatIngress = topo.hostNatIngress or { };
        prefixAuthority = declared.prefixAuthority or { };
        transit = semantic.transit or { };
        providerHandoffs = semantic.providerHandoffs or [ ];
        hostManagement = declared.hostManagement or null;
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
          overlayAttachments = model0.overlayAttachments;
          overlayAddressPools = model0.overlayAddressPools;
          trafficPaths = model0.trafficPaths;
          hostNatIngress = model0.hostNatIngress;
          sourceAudit = model.sourceAudit;
          dns = model0.dns;
        }
      ) model;
    in
    builtins.seq forced model;
}
