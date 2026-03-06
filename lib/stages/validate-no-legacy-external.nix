{ lib }:

siteKey: declared:

let
  policy = declared.policy or { };
  external = policy.external or null;
in
if external == null then
  true
else
  throw (
    builtins.toJSON {
      code = "E_POLICY_EXTERNAL_LEGACY_REMOVED";
      site = siteKey;
      path = [
        "policy"
        "external"
      ];
      message = "policy.external is removed; external routing must be derived only from explicit topology uplinks and policy rules";
      hints = [
        "Remove policy.external entirely."
      ];
    }
  )
