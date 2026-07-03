{ lib }:

let
  util = import ../correctness/util.nix { inherit lib; };

  forbiddenSourceKeys = [
    "bridgeName"
    "bridgeNames"
    "hostBridge"
    "hostUplink"
    "vlan"
    "vlanId"
    "renderer"
    "rendererTarget"
    "deploymentPlatform"
    "platform"
    "platformTarget"
    "containerRuntime"
    "nftablesChain"
    "systemdUnit"
    "ciscoCli"
    "junosConfig"
  ];

  forbiddenOutputKeys = forbiddenSourceKeys ++ [
    "deviceConfig"
    "platformSyntax"
    "rendererSyntax"
  ];

  rendererSelectorKeys = [
    "renderer"
    "rendererTarget"
    "deploymentPlatform"
    "platform"
    "platformTarget"
    "containerRuntime"
    "vendor"
    "deviceVendor"
    "routingMode"
    "firewallBackend"
  ];

  rendererSelectorValues = [
    "nixos"
    "containerlab"
    "docker"
    "podman"
    "nftables"
    "systemd"
    "cisco"
    "juniper"
  ];

  pathString = path: lib.concatStringsSep "." (map builtins.toString path);

  fail =
    siteKey: path: code: message: hints:
    util.throwError {
      inherit code;
      site = siteKey;
      path = path;
      message = message;
      hints = hints;
    };

  keyForbidden = keys: name: builtins.elem name keys;

  selectorValueForbidden =
    name: value:
    builtins.elem name rendererSelectorKeys
    && builtins.isString value
    && builtins.elem (lib.toLower value) rendererSelectorValues;

  validateValue =
    { mode
    , siteKey
    , forbiddenKeys
    , fieldCode
    , selectorCode
    , path
    , value
    ,
    }:
    if builtins.isAttrs value then
      builtins.all
        (
          name:
          let
            child = value.${name};
            childPath = path ++ [ name ];
          in
          if keyForbidden forbiddenKeys name then
            fail siteKey childPath fieldCode
              "${mode} field '${pathString childPath}' is platform-specific realization material"
              [
                "Keep renderer, bridge, VLAN, host-uplink, container runtime, nftables, systemd, and vendor syntax out of compiler behavior authority."
                "Put realization details in inventory, runtime facts, renderer contracts, or platform-specific renderers after platform-neutral behavior is complete."
              ]
          else if selectorValueForbidden name child then
            fail siteKey childPath selectorCode
              "${mode} field '${pathString childPath}' selects platform '${child}'"
              [
                "The compiler contract is platform-independent."
                "Renderer or deployment-platform selection belongs outside user-intent behavior and compiler output."
              ]
          else
            validateValue {
              inherit mode siteKey forbiddenKeys fieldCode selectorCode;
              path = childPath;
              value = child;
            }
        )
        (builtins.attrNames value)
    else if builtins.isList value then
      builtins.all
        (
          idx:
          validateValue {
            inherit mode siteKey forbiddenKeys fieldCode selectorCode;
            path = path ++ [ idx ];
            value = builtins.elemAt value idx;
          }
        )
        (lib.range 0 ((builtins.length value) - 1))
    else
      true;
in
{
  validateIntent =
    siteKey: declared:
    validateValue {
      mode = "intent";
      inherit siteKey;
      forbiddenKeys = forbiddenSourceKeys;
      fieldCode = "E_PLATFORM_INDEPENDENCE_SOURCE_FIELD";
      selectorCode = "E_PLATFORM_INDEPENDENCE_RENDERER_SELECTOR";
      path = [ ];
      value = declared;
    };

  validateOutput =
    siteKey: output:
    validateValue {
      mode = "compiler output";
      inherit siteKey;
      forbiddenKeys = forbiddenOutputKeys;
      fieldCode = "E_PLATFORM_INDEPENDENCE_OUTPUT_LEAK";
      selectorCode = "E_PLATFORM_INDEPENDENCE_OUTPUT_SELECTOR";
      path = [ ];
      value = output;
    };
}
