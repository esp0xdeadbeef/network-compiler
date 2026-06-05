{ lib }:

let
  util = import ../correctness/util.nix { inherit lib; };
  inherit (util) throwError;

  pathKey = path: builtins.toJSON path;

  mkBehaviorRef =
    outputPath: sourcePath: {
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
    lib.imap0
      (
        idx: value:
        let
          name = value.name or idx;
        in
        mkBehaviorRef (outputPrefix ++ [ idx ]) (sourcePrefix ++ [ name ])
      )
      values;

  overlayPoolRefs =
    overlayAddressPools:
    map
      (
        name:
        mkBehaviorRef
          [
            "overlayAddressPools"
            name
          ]
          [
            "overlayAddressPools"
            name
          ]
      )
      (lib.sort builtins.lessThan (builtins.attrNames overlayAddressPools));

  overlayAttachmentRefs =
    overlayAttachments:
    map
      (
        name:
        mkBehaviorRef
          [
            "overlayAttachments"
            name
          ]
          [
            "transport"
            "overlays"
            name
          ]
      )
      (lib.sort builtins.lessThan (builtins.attrNames overlayAttachments));

  requiredRefs =
    model:
    let
      tenants = model.tenants or [ ];
      services = model.services or [ ];
      isolationDecisions = model.isolationDecisions or [ ];
      relations = model.relations or [ ];
      trafficPaths = model.trafficPaths or [ ];
      overlayAttachments = model.overlayAttachments or { };
      overlayAddressPools = model.overlayAddressPools or { };
      hostNatIngress = model.hostNatIngress or { };
      ipv6 = model.ipv6 or { };
    in
    (indexedRefs [ "tenants" ] [ "segments" "tenants" ] tenants)
    ++ (indexedRefs [ "services" ] [ "communicationContract" "services" ] services)
    ++ (lib.imap0
      (
        idx: decision:
        if builtins.isAttrs (decision.source or null) then
          mkBehaviorRef [ "isolationDecisions" idx ] decision.source.sourcePath
        else
          mkBehaviorRef [ "isolationDecisions" idx ] [ "communicationContract" "isolationDecisions" idx ]
      )
      isolationDecisions)
    ++ (lib.imap0
      (
        idx: relation:
        relationAuditRef [ "relations" idx ] relation [ "communicationContract" "relations" idx ]
      )
      relations)
    ++ (lib.imap0
      (
        idx: path:
        mkBehaviorRef [
          "trafficPaths"
          idx
        ] [
          "communicationContract"
          "relations"
          (path.relationId or idx)
        ]
      )
      trafficPaths)
    ++ (overlayAttachmentRefs overlayAttachments)
    ++ (overlayPoolRefs overlayAddressPools)
    ++ (lib.optional (hostNatIngress != { })
      (mkBehaviorRef [ "hostNatIngress" ] [ "topology" "hostNatIngress" ]))
    ++ (lib.optional (ipv6 != { }) (mkBehaviorRef [ "ipv6" ] [ "ipv6" ]));

  auditRecords =
    model:
    if builtins.isAttrs (model.sourceAudit or null) then
      model.sourceAudit.behavior or [ ]
    else
      [ ];

  hasRequiredRecord =
    recordsByPath: required:
    let
      key = pathKey required.outputPath;
      record = recordsByPath.${key} or null;
    in
    record != null
    && (record.sourceClass or null) == "user-intent"
    && (record.authority or null) == "network-compiler"
    && builtins.isList (record.sourcePath or null);

  firstMissing =
    required: recordsByPath:
    let
      missing = lib.filter (ref: !(hasRequiredRecord recordsByPath ref)) required;
    in
    if missing == [ ] then null else builtins.head missing;

  validate =
    siteKey: model:
    let
      required = requiredRefs model;
      records = auditRecords model;
      recordsByPath = builtins.listToAttrs (
        map
          (record: {
            name = pathKey (record.outputPath or [ ]);
            value = record;
          })
          records
      );
      missing = firstMissing required recordsByPath;
    in
    if missing == null then
      true
    else
      throwError {
        code = "E_COMPILER_BEHAVIOR_SOURCE_AUDIT";
        site = siteKey;
        path = missing.outputPath;
        message = "compiler behavior output lacks a user-intent source audit reference";
        hints = [
          "Every compiler behavior-creating output must have sourceClass = \"user-intent\"."
          "Keep compiler source audit authority scoped to network-compiler behavior outputs."
          "Do not use compiler source-audit records for CPM realization binders or renderer materialization fields."
        ];
      };

  attach =
    siteKey: model:
    let
      audited = model // {
        sourceAudit = {
          behavior = requiredRefs model;
        };
      };
      _valid = validate siteKey audited;
    in
    builtins.seq _valid audited;
in
{
  inherit mkBehaviorRef requiredRefs validate attach;
}
