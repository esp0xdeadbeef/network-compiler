{
  lib,
  normalizeSite,
  buildModel,
}:

siteKey: declared:

let
  semantic = normalizeSite declared;
in
buildModel siteKey declared semantic
