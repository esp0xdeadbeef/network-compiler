{ lib }:

key:

let
  m = builtins.match "([^.]*)\\.(.*)" key;
in
if m == null then
  {
    enterprise = "default";
    siteName = key;
  }
else
  {
    enterprise = builtins.elemAt m 0;
    siteName = builtins.elemAt m 1;
  }
