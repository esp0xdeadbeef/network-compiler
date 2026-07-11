{ lib }:

let
  util = import ../correctness/util.nix { inherit lib; };
  inherit (util) throwError;

  pathKey = path: builtins.toJSON path;

  refs = import ./source-audit-required-refs.nix { inherit lib; };
  inherit (refs) mkBehaviorRef requiredRefs;

  auditRecords =
    model:
    if builtins.isAttrs (model.sourceAudit or null) then
      model.sourceAudit.behavior or [ ]
    else
      [ ];

  mismatchedRecord =
    recordsByPath: required:
    let
      key = pathKey required.outputPath;
      record = recordsByPath.${key} or null;
    in
    if record == null then
      { reason = "missing"; }
    else if (record.sourceClass or null) != "user-intent" then
      {
        reason = "wrong-source-class";
        foundClass = record.sourceClass or null;
      }
    else if (record.authority or null) != "network-compiler" then
      {
        reason = "wrong-authority";
        foundAuthority = record.authority or null;
      }
    else if !(builtins.isList (record.sourcePath or null)) then
      { reason = "invalid-source-path"; }
    else
      null;

  hasRequiredRecord =
    recordsByPath: required:
    (mismatchedRecord recordsByPath required) == null;

  firstGap =
    required: recordsByPath:
    let
      gaps = lib.filter (ref: (mismatchedRecord recordsByPath ref) != null) required;
    in
    if gaps == [ ] then { required = null; mismatch = null; } else {
      required = builtins.head gaps;
      mismatch = mismatchedRecord recordsByPath (builtins.head gaps);
    };

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
      gap = firstGap required recordsByPath;
      gapRequired = gap.required;
      gapMismatch = gap.mismatch;
      gapMessage =
        if gapMismatch == null || gapMismatch.reason == "missing" then
          "compiler behavior output lacks a user-intent source audit reference"
        else if gapMismatch.reason == "wrong-source-class" then
          "compiler behavior output has non-intent sourceClass: found \"${gapMismatch.foundClass or "null"}\", expected \"user-intent\""
        else if gapMismatch.reason == "wrong-authority" then
          "compiler behavior output has non-compiler authority: found \"${gapMismatch.foundAuthority or "null"}\", expected \"network-compiler\""
        else
          "compiler behavior output has an invalid source audit reference";
    in
    if gapRequired == null then
      true
    else
      throwError {
        code = "E_COMPILER_BEHAVIOR_SOURCE_AUDIT";
        site = siteKey;
        path = gapRequired.outputPath;
        message = gapMessage;
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
