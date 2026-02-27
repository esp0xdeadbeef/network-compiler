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

  normalizeError =
    err:
    if builtins.isString err then
      {
        code = "E_ASSERT";
        site = null;
        path = [ ];
        message = err;
        hints = [ ];
      }
    else if builtins.isAttrs err then
      {
        code = err.code or "E_ASSERT";
        site = err.site or null;
        path = toList (err.path or [ ]);
        message = err.message or (err.msg or "error");
        hints = toList (err.hints or [ ]);
      }
    else
      {
        code = "E_ASSERT";
        site = null;
        path = [ ];
        message = "error";
        hints = [ ];
      };

  throwError = err: throw (builtins.toJSON (normalizeError err));
in
{
  inherit normalizeError throwError;
}
