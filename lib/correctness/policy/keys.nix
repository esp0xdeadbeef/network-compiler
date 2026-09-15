{ lib }:

let
  subjectKey =
    subj:
    if subj.kind == "tenant" then
      "tenant:${subj.name}"
    else if subj.kind == "tenant-set" then
      "tenant-set:${lib.concatStringsSep "," (lib.sort builtins.lessThan subj.members)}"
    else if subj.kind == "service" then
      "service:${subj.name}"
    else if subj ? scope then
      "external-scope:${subj.scope}"
    else if subj ? name then
      "external:${subj.name}"
    else
      "external";

  targetKey =
    target:
    if target == "any" then
      "any"
    else if target.kind == "service" then
      "service:${target.name}"
    else
      subjectKey target;
in
{
  inherit subjectKey targetKey;
}
