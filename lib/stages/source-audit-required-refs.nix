{ lib }:

let
  mkBehaviorRef = outputPath: sourcePath: {
    outputPath = outputPath;
    sourceClass = "user-intent";
    sourcePath = sourcePath;
    authority = "network-compiler";
  };

  relationAuditRef =
    outputPath: relation: fallbackSourcePath:
    if builtins.isAttrs (relation.source or null) && relation.source ? sourceAudit then
      mkBehaviorRef outputPath relation.source.sourceAudit.sourcePath
    else
      mkBehaviorRef outputPath fallbackSourcePath;

  indexedRefs =
    outputPrefix: sourcePrefix: values:
    lib.imap0 (
      idx: value:
      let
        name = value.name or idx;
      in
      mkBehaviorRef (outputPrefix ++ [ idx ]) (sourcePrefix ++ [ name ])
    ) values;

  overlayPoolRefs =
    overlayAddressPools:
    map (name: mkBehaviorRef [ "overlayAddressPools" name ] [ "overlayAddressPools" name ]) (
      lib.sort builtins.lessThan (builtins.attrNames overlayAddressPools)
    );

  overlayAttachmentRefs =
    overlayAttachments:
    map (name: mkBehaviorRef [ "overlayAttachments" name ] [ "transport" "overlays" name ]) (
      lib.sort builtins.lessThan (builtins.attrNames overlayAttachments)
    );
in
{
  inherit mkBehaviorRef;

  requiredRefs =
    model:
    let
      tenants = model.tenants or [ ];
      services = model.services or [ ];
      isolationDecisions = model.isolationDecisions or [ ];
      relations = model.relations or [ ];
      trafficPaths = model.trafficPaths or [ ];
      sharedServicePolicyAtoms = (model.accessSpaceDiscovery or { }).sharedServicePolicyAtoms or [ ];
      overlayAttachments = model.overlayAttachments or { };
      overlayAddressPools = model.overlayAddressPools or { };
      hostNatIngress = model.hostNatIngress or { };
      ipv6 = model.ipv6 or { };
      prefixAuthority = model.prefixAuthority or { };
      dns = model.dns or { };
    in
    (indexedRefs [ "tenants" ] [ "segments" "tenants" ] tenants)
    ++ (indexedRefs [ "services" ] [ "communicationContract" "services" ] services)
    ++ (lib.imap0 (
      idx: decision:
      if builtins.isAttrs (decision.source or null) then
        mkBehaviorRef [ "isolationDecisions" idx ] decision.source.sourcePath
      else
        mkBehaviorRef [ "isolationDecisions" idx ] [ "communicationContract" "isolationDecisions" idx ]
    ) isolationDecisions)
    ++ (lib.imap0 (
      idx: relation:
      relationAuditRef [ "relations" idx ] relation [
        "communicationContract"
        "relations"
        idx
      ]
    ) relations)
    ++ (lib.imap0 (
      idx: path:
      mkBehaviorRef
        [
          "trafficPaths"
          idx
        ]
        [
          "communicationContract"
          "relations"
          (path.relationId or idx)
        ]
    ) trafficPaths)
    ++ (lib.imap0 (
      idx: atom:
      let
        outputPath = [
          "accessSpaceDiscovery"
          "sharedServicePolicyAtoms"
          idx
        ];
      in
      if builtins.isAttrs (atom.source or null) then
        mkBehaviorRef outputPath atom.source.sourcePath
      else
        mkBehaviorRef outputPath [
          "communicationContract"
          "sharedServicePolicyAtoms"
          (atom.id or idx)
        ]
    ) sharedServicePolicyAtoms)
    ++ (overlayAttachmentRefs overlayAttachments)
    ++ (overlayPoolRefs overlayAddressPools)
    ++ (lib.optional (hostNatIngress != { }) (
      mkBehaviorRef [ "hostNatIngress" ] [ "topology" "hostNatIngress" ]
    ))
    ++ (lib.optional (prefixAuthority != { }) (
      mkBehaviorRef [ "prefixAuthority" ] [ "prefixAuthority" ]
    ))
    ++ (lib.optional (dns != { }) (mkBehaviorRef [ "dns" ] [ "recursiveDnsIntent" ]))
    ++ (lib.optional (ipv6 != { }) (mkBehaviorRef [ "ipv6" ] [ "ipv6" ]));
}
