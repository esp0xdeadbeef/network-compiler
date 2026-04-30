{ lib }:

{
  site,
  util,
  seg,
}:

let
  inherit (util) ensure;

  _shape = ensure (builtins.isAttrs seg) {
    code = "E_INPUT_ATTACHMENT_SHAPE";
    site = site.siteName or null;
    path = [
      "topology"
      "nodes"
    ];
    message = "attachment must be an attrset";
    hints = [ "Use { kind = \"tenant\"; name = \"...\"; }." ];
  };

  kind = seg.kind or null;
  name = seg.name or null;

  _kind = ensure (kind != null) {
    code = "E_INPUT_ATTACHMENT_MISSING_KIND";
    site = site.siteName or null;
    path = [
      "topology"
      "nodes"
    ];
    message = "attachment.kind is required";
    hints = [ "Set attachment.kind = \"tenant\" or \"service\"." ];
  };

  _name = ensure (name != null) {
    code = "E_INPUT_ATTACHMENT_MISSING_NAME";
    site = site.siteName or null;
    path = [
      "topology"
      "nodes"
    ];
    message = "attachment.name is required";
    hints = [ "Set attachment.name = \"...\"." ];
  };
in
if kind == "tenant" then
  "tenants:${name}"
else if kind == "service" then
  "services:${name}"
else
  "segments:${name}"
