{ lib }:

siteKey: declared:

let
  legacyPolicy = declared.policy or null;
in
if legacyPolicy == null then
  true
else
  throw (
    builtins.toJSON {
      code = "E_LEGACY_POLICY_REMOVED";
      site = siteKey;
      path = [ "policy" ];
      message = "policy is removed; use communicationContract instead";
      hints = [
        "Rename policy to communicationContract."
        "Use communicationContract.trafficTypes, communicationContract.services, and communicationContract.relations."
      ];
    }
  )
