{ lib }:

let
  util = import ../correctness/util.nix { inherit lib; };
  fieldClasses = import ../field-classes.nix { inherit lib; };

  forbiddenKeys = [
    "upstreamEmulation"
    "providerAccess"
  ];

  realizationTechnologyValues = [
    "dhcp"
    "ppp"
    "pppoe"
    "xvlan"
  ];

  pathString = path: lib.concatStringsSep "." (map builtins.toString path);

  hasForbiddenKey = name: builtins.elem name forbiddenKeys;

  isRealizationSelector =
    name: value:
    builtins.elem name [
      "technology"
      "handoff"
      "distributionTechnology"
    ]
    && builtins.isString value
    && builtins.elem (lib.toLower value) realizationTechnologyValues;

  derivedAt = fieldClasses.classifyDerived;

  fail =
    siteKey: path: code: message: hints:
    util.throwError {
      inherit code;
      site = siteKey;
      path = path;
      message = message;
      hints = hints;
    };

  validateValue =
    siteKey: path: value:
    if builtins.isAttrs value then
      builtins.all (
        name:
        let
          child = value.${name};
          childPath = path ++ [ name ];
        in
        if hasForbiddenKey name then
          fail siteKey childPath "E_INTENT_SOURCE_BOUNDARY_SIDE_CHANNEL"
            "intent field '${pathString childPath}' is a downstream side channel, not source intent"
            [
              "Model provider/access behavior through normal core, access, service, external, policy, and route intent."
              "Put realization-only fixture metadata in inventory/HAT data, not intent.nix."
            ]
        else if isRealizationSelector name child then
          fail siteKey childPath "E_INTENT_SOURCE_BOUNDARY_REALIZATION_TECHNOLOGY"
            "intent field '${pathString childPath}' selects realization technology '${child}'"
            [
              "Keep DHCP, PPP, PPPoE, xVLAN, and similar technology choices in inventory or HAT fixture metadata."
              "Intent may select the access/service endpoint and policy path, but not renderer or substrate technology."
            ]
        else if derivedAt childPath != null then
          let
            d = derivedAt childPath;
          in
          fail siteKey childPath "E_INTENT_SOURCE_BOUNDARY_DERIVED_AS_INPUT"
            "intent field '${pathString childPath}' (${d.field}) is derived and shall not be supplied as input"
            [
              "Remove '${d.field}'; it is computed by ${d.owningStep} from ${d.derivedFrom}."
              "A derived path or stage list fails closed because it can bypass the canonical staged fabric."
            ]
        else
          validateValue siteKey childPath child
      ) (builtins.attrNames value)
    else if builtins.isList value then
      builtins.all (idx: validateValue siteKey (path ++ [ idx ]) (builtins.elemAt value idx)) (
        lib.range 0 ((builtins.length value) - 1)
      )
    else
      true;

in
siteKey: declared: validateValue siteKey [ ] declared
