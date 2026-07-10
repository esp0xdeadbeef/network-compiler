{ lib }:

# FS-590-HDS-010-SDS-010-SMS-030: Discovery Transport Explicitness
# Enforces that discovery transport classes (multicast, broadcast, relay,
# proxy, printer, casting, media) are explicitly declared and do not leak
# from renderer defaults or service-class inference.
#
# SN1 (DISCOVERY_TRANSPORT_NOT_EXPLICIT):
#   Printer service class with no discovery transport declaration →
#   reject with DISCOVERY_TRANSPORT_NOT_EXPLICIT.
# SN2 (RENDERER_DEFAULT_DISCOVERY_TRANSPORT_DENIED):
#   renderer default would create multicast discovery but policy lacks
#   explicit declaration → reject with RENDERER_DEFAULT_DISCOVERY_TRANSPORT_DENIED.

siteKey: service:
let
  util = import ../../correctness/util.nix { inherit lib; };
  inherit (util) ensure;

  has = attr: attrs: builtins.isAttrs attrs && builtins.hasAttr attr attrs;
  isNonEmptyString = value: builtins.isString value && value != "";

  serviceName = service.service or "unnamed";
  serviceClass = service.serviceClass or null;
  discovery = service.discovery or { };
  protocol = discovery.protocol or null;

  # Service classes for which discovery transport must be explicitly declared.
  # Per SMS-030, these classes imply discovery capability and must not leave
  # transport to renderer defaults or service-class inference.
  discoveryTransportClasses = [
    "printer"
    "media-receiver"
    "media-control"
    "casting"
    "media-device"
    "chromecast"
  ];

  # SN1: DISCOVERY_TRANSPORT_NOT_EXPLICIT
  # When a shared service belongs to a discovery-relevant service class and
  # the discovery transport protocol is not explicitly declared, reject with
  # DISCOVERY_TRANSPORT_NOT_EXPLICIT. Discovery transport must be explicitly
  # modeled, not inferred from service class or renderer defaults.
  _transportNotExplicit =
    if serviceClass != null
       && builtins.elem serviceClass discoveryTransportClasses
       && !isNonEmptyString protocol then
      ensure false {
        code = "DISCOVERY_TRANSPORT_NOT_EXPLICIT";
        site = siteKey;
        path = [
          "profileManifest"
          "sharedServiceMatrix"
          serviceName
          "discovery"
          "protocol"
        ];
        message = "service '${serviceName}' (serviceClass=${serviceClass})"
          + " lacks explicit discovery transport declaration;"
          + " discovery transport must be explicitly modeled,"
          + " not inferred from service class or renderer defaults";
        hints = [
          "Declare discovery.protocol and discovery.direction for the shared service."
          "Service classes (printer, media-receiver, casting etc.) do not create discovery transport by themselves."
          "Multicast, broadcast, relay, proxy, and reflection behavior requires explicit declaration."
        ];
      }
    else
      true;

  # SN2: RENDERER_DEFAULT_DISCOVERY_TRANSPORT_DENIED
  # When the intent explicitly sets a flag signaling that renderer defaults
  # would create multicast transport but the discovery policy lacks an
  # explicit multicast, broadcast, relay, proxy, or reflection declaration,
  # reject with RENDERER_DEFAULT_DISCOVERY_TRANSPORT_DENIED.
  _rendererDefaultTransport =
    if has "inferTransportFromDefaultMulticast" discovery
       && discovery.inferTransportFromDefaultMulticast == true then
      ensure false {
        code = "RENDERER_DEFAULT_DISCOVERY_TRANSPORT_DENIED";
        site = siteKey;
        path = [
          "profileManifest"
          "sharedServiceMatrix"
          serviceName
          "discovery"
          "inferTransportFromDefaultMulticast"
        ];
        message = "service '${serviceName}' discovery transport must not be"
          + " inferred from renderer-default multicast;"
          + " renderer default discovery transport creation is denied"
          + " without explicit multicast, broadcast, relay, proxy,"
          + " or reflection declaration";
        hints = [
          "Declare explicit discovery transport policy instead of relying on renderer defaults."
          "Multicast, broadcast, relay, proxy, and reflection behavior requires explicit declaration."
          "Remove inferTransportFromDefaultMulticast and declare discovery.protocol and discovery.direction explicitly."
        ];
      }
    else
      true;
in
builtins.deepSeq [ _transportNotExplicit _rendererDefaultTransport ] true
