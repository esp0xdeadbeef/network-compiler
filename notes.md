# access nodes are missing incomming routes from different vlans.




./lib/compile/validate.nix should enforce forbidden ranges from inputs.nix. Don't generate, just throw, and suggest `[];` empty array.


./lib/compile/routing/tenant-lan.nix, 
  delegatedV6 =
    let
      normalize48 =
        addr:
        let
          parts = lib.splitString "/" addr;
          ip = builtins.elemAt parts 0;
          plen = builtins.elemAt parts 1;
          hextets = lib.take 3 (lib.splitString ":" ip);
        in
        if plen != "48" then null else lib.concatStringsSep ":" hextets;


Should use the official nix.networking ipv6 addresses, not invent the wheel, never ever invent the wheel self. If you have a library, use it!


grep -R for lan (dns names) 
