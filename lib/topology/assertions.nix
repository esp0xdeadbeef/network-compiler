{ lib }:

{
  policyNodeName,
  coreNodeName,
  accessNodePrefix,
  forbiddenVlanRanges,
}:

let
  forbiddenRanges = if forbiddenVlanRanges == null then [ ] else forbiddenVlanRanges;

  _assertPolicyNodeName = lib.assertMsg (builtins.isString policyNodeName && policyNodeName != "") ''
    topology: invalid policyNodeName
  '';

  _assertCoreNodeName = lib.assertMsg (builtins.isString coreNodeName && coreNodeName != "") ''
    topology: invalid coreNodeName
  '';

  _assertAccessNodePrefix =
    lib.assertMsg (builtins.isString accessNodePrefix && accessNodePrefix != "")
      ''
        topology: invalid accessNodePrefix
      '';

  _assertForbiddenRanges = lib.assertMsg (
    builtins.isList forbiddenRanges
    && lib.all (r: builtins.isAttrs r && r ? from && r ? to) forbiddenRanges
  ) "topology: invalid forbiddenVlanRanges";

in
builtins.seq _assertPolicyNodeName (
  builtins.seq _assertCoreNodeName (
    builtins.seq _assertAccessNodePrefix (builtins.seq _assertForbiddenRanges true)
  )
)
