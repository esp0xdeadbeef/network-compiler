# inputs should define the nat mode for cores, or crash:

Minimal and explicit:

```nix
nat = {  
  mode = "none";     # no nat
};
```

or

```nix
nat = {  
  mode = "custom";  
  
  egress = {  
    strategy = "masquerade";  
    source = "interface";  
  };  
  
  ingress = {  
    allowPortForward = true;  
    hairpin = false;  
  };  
};
```

Only two semantic states exist.

So:
(node.role == "core") AND (nat undefined)
    → compiler error
