{ lib }:

let

  isClass =
    s:
    builtins.isString s
    && (
      s == "default"
      || s == "internet"
      || s == "none"
      || (lib.hasPrefix "site:" s && (builtins.stringLength s) > (builtins.stringLength "site:"))
      || (lib.hasPrefix "overlay:" s && (builtins.stringLength s) > (builtins.stringLength "overlay:"))
    );

  assertClasses =
    ctx: xs:
    let
      bad = lib.filter (x: !(isClass x)) (if xs == null then [ ] else xs);
    in
    lib.assertMsg (bad == [ ]) ''
      Invalid route class(es) in ${ctx}:

        ${lib.concatStringsSep "\n    - " (map builtins.toString bad)}

      Valid classes:
        - default
        - internet
        - site:<name>
        - overlay:<name>
        - none
    '';

  normalize =
    xs:
    let
      xs0 = if xs == null then [ ] else xs;
      _ok = assertClasses "route class list" xs0;
    in
    lib.unique xs0;

in
{
  inherit isClass assertClasses normalize;
}
