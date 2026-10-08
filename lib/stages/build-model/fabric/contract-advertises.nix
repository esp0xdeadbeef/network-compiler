# FS-470: remote-egress advertisement normalization, split out of
# build-model/fabric/contract-prefixes.nix so that module stays under the
# tracked LOC soft limit.
{ lib, siteKey }:

let
  util = import ../../../correctness/util.nix { inherit lib; };
  inherit (util) throwError;
in
{
  make =
    {
      declaredOwnershipPrefixStrings,
      declaredTenantPrefixesByName,
    }:
    nodeName: node:
    let
      raw = node.advertises or null;
      path = [
        "topology"
        "nodes"
        nodeName
        "advertises"
      ];
      spec = "FS-470 Remote Egress over WireGuard; owning item: FS-470";
      fail =
        reason: hints:
        throwError {
          code = "E_CONTRACT_ADVERTISES";
          site = siteKey;
          inherit path;
          message = "topology.nodes.${nodeName}.advertises ${reason} (FS-470 Remote Egress over WireGuard).";
          inherit spec;
          inherit hints;
        };
      resolveEntry =
        idx: entry:
        if builtins.isString entry then
          if builtins.elem entry declaredOwnershipPrefixStrings then
            [ entry ]
          else
            fail "names prefix '${entry}', which is not a declared ownership prefix" [
              "Advertise a declared tenant prefix or a prefix from ownership.prefixes."
            ]
        else if builtins.isAttrs entry && (entry.kind or null) == "tenant" then
          let
            name = entry.name or null;
          in
          if !(builtins.isString name) then
            fail "entry ${toString idx} of kind 'tenant' must name the tenant" [
              "Set { kind = \"tenant\"; name = \"<tenant>\"; }."
            ]
          else if !(builtins.hasAttr name declaredTenantPrefixesByName) then
            fail "entry ${toString idx} names tenant '${name}', which is not a declared ownership tenant" [
              "Reference a tenant declared in ownership.prefixes."
            ]
          else
            declaredTenantPrefixesByName.${name}
        else
          fail "entry ${toString idx} must be a prefix string or { kind = \"tenant\"; name = ...; }" [
            "Use a CIDR string or a tenant reference."
          ];
    in
    if raw == null then
      [ ]
    else if builtins.isList raw then
      lib.unique (lib.concatLists (lib.imap0 (idx: entry: resolveEntry idx entry) raw))
    else
      fail "must be a list" [ "Declare advertises as a list of prefixes or tenant references." ];
}
