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
      code = "E_SUPERSEDED_CONTRACT";
      site = siteKey;
      path = [ "policy" ];
      message = "top-level intent key 'policy' is removed; use communicationContract";
      hints = [
        "Rename policy to communicationContract."
        "Use communicationContract.trafficTypes, communicationContract.services, and communicationContract.relations."
      ];
      spec = "FS-081 Superseded-Contract Rejection";
    }
  )
