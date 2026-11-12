{ lib }:

let
  toList =
    x:
    if x == null then
      [ ]
    else if builtins.isList x then
      x
    else
      [ x ];

  # FS-025-HDS-010-SDS-010-SMS-030: every failure record carries the resolved
  # FS-025 mode, so a reader can tell whether the condition forbids emission,
  # denies a flow, or only requires visibility. The vocabulary is the FS-025 one,
  # verbatim: `render-abort`, `runtime-deny`, `visibility-only`.
  #
  # Everything reaching `throwError` here terminates the compile before any
  # artifact is released to the next stage, which is `render-abort` by
  # definition (FS-025-HDS-010-SDS-010-SMS-020). A site that raises a condition
  # with a different governing mode sets `mode` on the error record; it is
  # carried through rather than defaulted, so a substitution cannot happen
  # silently.
  failureModes = [
    "render-abort"
    "runtime-deny"
    "visibility-only"
  ];

  resolveMode =
    err:
    let
      declared = if builtins.isAttrs err then err.mode or err.failureMode or null else null;
    in
    if builtins.isString declared && builtins.elem declared failureModes then
      declared
    else
      "render-abort";

  normalizeError =
    err:
    if builtins.isString err then
      {
        code = "E_ASSERT";
        site = null;
        path = [ ];
        message = err;
        hints = [ ];
        mode = resolveMode err;
      }
    else if builtins.isAttrs err then
      {
        code = err.code or "E_ASSERT";
        site = err.site or null;
        path = toList (err.path or [ ]);
        message = err.message or (err.msg or "error");
        hints = toList (err.hints or [ ]);
        mode = resolveMode err;
      }
      // lib.optionalAttrs (err ? spec) { inherit (err) spec; }
    else
      {
        code = "E_ASSERT";
        site = null;
        path = [ ];
        message = "error";
        hints = [ ];
        mode = "render-abort";
      };

  throwError = err: throw (builtins.toJSON (normalizeError err));
in
{
  inherit failureModes normalizeError throwError;
}
