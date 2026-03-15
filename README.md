
# nixos-network-compiler

A deterministic compiler that converts **network intent** into a **platform-independent network model**.

The compiler does **not** generate device configuration.  
Instead it produces a stable intermediate representation that later stages can realize and render.

* * *

# Disclaimer

This project exists primarily to support my own infrastructure.

If it happens to be useful to others, great — but **pin a specific version** (see the Nix manual for flakes).

The internal schema may change between versions.  
Backward compatibility is **not guaranteed**.

Pull requests are welcome, but changes that conflict with the architectural model are unlikely to be merged.

* * *

# Reality Check

If your goal is simply:

site-a ↔ site-b

over a tunnel, this project is **completely unnecessary**.

You could solve that with something like:

```bash
ip route add 10.20.0.0/24 via 10.0.0.2 dev wg0
```

Done.

This repository exists because I chose to build something **much more complicated** instead.

In other words:

> This project is occasionally a **nuclear reactor used to boil water**.

The goal is not just connectivity.

The goal is **deterministic, reproducible network behavior**.

Once networks require things like:

* deterministic topology construction
    
* policy enforcement placement
    
* routing authority boundaries
    
* renderer-agnostic configuration
    
* reproducible addressing
    

the simple solutions stop scaling very quickly.

So yes — for connecting two sites, this is massive overkill.

But the moment the network stops being trivial, the structure starts to make sense.

* * *

# What this project does

The compiler converts a **high-level network description** into a deterministic **network model**.

Input describes:

* sites
* tenants
* services
* communication policy
* topology
* address pools
* overlays
    

Output describes:

* normalized topology
* deterministic addressing
* uplink structure
* communication contracts
* attachment relationships
* routing domains
* traversal ordering
    

The result is a **platform-independent description of a network site**.

Later stages can turn this into:

* router configuration
* firewall rules
* containerlab labs
* NixOS modules
* simulation environments
    

* * *

# Position in the architecture

The project is part of a multi-stage pipeline.

| Layer | Responsibility |
| --- | --- |
| **Compiler** | defines communication semantics |
| **Forwarding Model** | constructs deterministic forwarding structure |
| **Control plane model** | derives control-plane mechanisms |
| **Renderer** | generates platform configuration |

Pipeline:

intent  
  ↓  
compiler  
  ↓  
forwarding model  
  ↓  
control plane model
  ↓  
renderer

This repository implements the **compiler stage**.

* * *

# Compiler responsibilities

The compiler defines **what communication must be possible**.

It does **not** decide:

* routing protocols
* route distribution
* device configuration
* firewall implementation
    

Those decisions belong to later stages.

The compiler produces a **normalized network model** that is:

* deterministic
* platform neutral
* renderer agnostic

* * *

# Policy model

Network behavior is defined through a **communication contract**.

The contract describes:

| Component | Purpose |
| --- | --- |
| `trafficTypes` | protocol definitions |
| `services` | logical services provided by hosts |
| `relations` | allowed / denied communication |

Example relation:

```nix
{  
  id = "allow-admin-to-mgmt-dns";  
  priority = 100;  
  
  from = {  
    kind = "tenant";  
    name = "admin";  
  };  
  
  to = {  
    kind = "service";  
    name = "dns-site";  
  };  
  
  trafficType = "dns";  
  action = "allow";  
}
```

This defines **behavioral intent**, not firewall rules.

* * *

# Topology model

Topology describes **network execution structure**.

Nodes represent **forwarding units**.

Example:

Access → Policy → Upstream Selector → Core

Each node has a role:

| Role | Responsibility |
| --- | --- |
| `access` | tenant attachment |
| `policy` | enforcement |
| `upstream-selector` | path selection |
| `core` | external connectivity |

The compiler ensures topology correctness:

* no disconnected nodes
* valid uplink definitions
* correct role presence
* deterministic link ordering
    

* * *

# Deterministic guarantees

For a given input, the compiler always produces the same output.

The resulting model guarantees:

* deterministic address allocation
* stable topology ordering
* explicit authority boundaries
* validated policy structure
    

The output is suitable for **further compilation stages**.

* * *

# Running the compiler

Compile a site definition:

```bash
nix run .#compile examples/single-wan/inputs.nix
```


Compile all examples:

```bash
./compile-all-examples.sh
```

Debug compilation:

```bash
nix run .#debug examples/single-wan/inputs.nix
```

# Example output structure

The compiler produces structured JSON:

sites  
 └ enterprise  
     └ site  
         ├ communicationContract  
         ├ domains  
         ├ hosts  
         ├ transport  
         ├ uplinks  
         ├ routerLoopbacks  
         └ transit

This output becomes the **input to the forwarding model stage**.

* * *

# ISA-88 interpretation

The architecture loosely follows ISA-88 responsibility separation.

| ISA-88 | Meaning here |
| --- | --- |
| Enterprise | administrative grouping |
| Site | authority boundary |
| Process Cell | allowed communication behavior |
| Unit | forwarding execution context |
| Equipment Module | responsibility of a unit |
| Control Module | implementation mechanism |

The compiler stops at **Process Cell semantics**.

Later stages realize these semantics into operational networks.

* * *

# Architectural invariant

The system maintains one rule:

behavior  
  → forwarding  
  → realization  
  → configuration

Each stage reduces ambiguity without introducing platform assumptions.

* * *

# Tests

Run the test suite:

```bash
nix run .#check
```

The test suite includes:

* positive examples
    
* negative validation tests
    
* regression tests
    
