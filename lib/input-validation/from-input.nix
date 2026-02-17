{ lib }:

args:

let
  raw = if builtins.isAttrs args && args ? topology then args.topology else args;

  topoInput = if builtins.isFunction raw then raw { } else raw;

  isAttrs = builtins.isAttrs topoInput;

  has = name: isAttrs && builtins.hasAttr name topoInput;

  isResolved = isAttrs && has "nodes" && has "links" && has "ulaPrefix" && has "tenantV4Base";

  isSingleSite =
    isAttrs
    && has "policyAccessTransitBase"
    && has "corePolicyTransitVlan"
    && has "ulaPrefix"
    && has "tenantV4Base";

  evalSingleSite = import ./single-site.nix { inherit lib; };
  evalMultiSite = import ./multi-site.nix { inherit lib; };

in
if isResolved then
  import ../compile/compile.nix {
    inherit lib;
    model = topoInput;
  }
else if isSingleSite then
  evalSingleSite topoInput
else if isAttrs then
  evalMultiSite topoInput
else
  throw "eval/from-input: unsupported topology input shape"
