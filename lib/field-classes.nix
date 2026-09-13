{ lib }:

let

  matchSegments =
    pattern: path:
    let
      n = builtins.length pattern;
      len = builtins.length path;
      starts = lib.range 0 (len - n);
      at =
        start:
        builtins.all (
          i:
          let
            p = builtins.elemAt pattern i;
            v = builtins.elemAt path (start + i);
          in
          p == null || p == v
        ) (lib.range 0 (n - 1));
    in
    n == 0 || builtins.any at starts;

  derivedFields = [
    {
      id = "dns-resolver-path";

      match = path: matchSegments [ null "relation" "resolverPath" ] path;
      field = "localDnsSharingIntent[].relation.resolverPath";
      owningStep = "traffic-paths (pathStagesFor)";
      derivedFrom = "requesterScope, upstreamResolver, canonical stages";
      fault = "E_INTENT_SOURCE_BOUNDARY_DERIVED_AS_INPUT";
    }
    {
      id = "overlay-traversal-list";

      match = path: builtins.elem "mustTraverse" path;
      field = "mustTraverse";
      owningStep = "overlay-attachments (canonical path)";
      derivedFrom = "overlay core, roles";
      fault = "E_INTENT_SOURCE_BOUNDARY_DERIVED_AS_INPUT";
    }
    {
      id = "relation-stage-path";

      match =
        path:
        (matchSegments [ "relations" null "stagePath" ] path)
        || (matchSegments [ "relations" null "nodePath" ] path);
      field = "relations[].stagePath | nodePath";
      owningStep = "traffic-paths (pathStagesFor)";
      derivedFrom = "relations, topology.links, roles";
      fault = "E_INTENT_SOURCE_BOUNDARY_DERIVED_AS_INPUT";
    }
    {

      id = "overlay-canonical-path";
      match =
        path:
        (matchSegments [ null "canonicalPath" ] path)
        || (matchSegments [ null "overlayAttachments" null "canonicalPath" ] path);
      field = "overlayAttachments[].canonicalPath";
      owningStep = "overlay-attachments";
      derivedFrom = "overlay core, roles";
      fault = "E_INTENT_SOURCE_BOUNDARY_DERIVED_AS_INPUT";
    }
  ];

  classifyDerived =
    path:
    let
      matches = builtins.filter (f: f.match path) derivedFields;
    in
    if matches == [ ] then null else builtins.head matches;

in
{
  inherit derivedFields classifyDerived;
}
