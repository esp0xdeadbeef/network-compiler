# nixos-network-compiler

A pure Nix network topology compiler.

This repository defines a deterministic pipeline:

topology → resolution → routing → rendering

It produces structured network graphs and systemd-networkd
configurations without builds, without runtime state, and without
impure evaluation.

There is no legacy compatibility layer.
There is no historical migration logic.
There is no implicit behavior.

Everything is explicit and reproducible.

---

## Design Principles

- Pure evaluation
- Deterministic outputs
- No file I/O inside the library
- No environment variable reads
- No hidden defaults
- No legacy abstractions

The compiler operates entirely on data structures.

---

## Pipeline

### 1. Topology

`lib/topology-gen.nix`

Defines:

- Nodes
- Links
- VLAN allocation
- Address allocation

Links use:

- `kind = "lan"` for broadcast segments
- `kind = "p2p"` for point-to-point links
- `carrier = "lan" | "wan" | "nebula"`
- `scope = "internal" | "external"`

---

### 2. Resolution

`lib/topology-resolve.nix`

Normalizes and enriches topology:

- Expands endpoints
- Computes interface structures
- Prepares for routing stage

---

### 3. Routing

`lib/compile/routing-gen.nix`

Adds:

- Default routes
- Tenant subnet routes
- Core routing rules
- RA prefixes

No routing logic exists in topology.
No topology logic exists in routing.

---

### 4. Rendering

`lib/render/networkd`

Transforms compiled graph into systemd-networkd definitions.

Rendering is mechanical.
No routing decisions are made here.

---

## Debugging

Debug output is pure.

Run:

    ./dev/debug.sh

Optional secrets injection:

    ./dev/debug.sh ../../secrets/file.yaml

Secrets are passed as JSON.
The compiler never reads files.
The compiler never reads environment variables.

---

## Topology Model

### Nodes

    {
      ifs = {
        lan = "lan0";
        wan = "wan0";
      };
    }

### Links

    {
      kind = "lan" | "p2p";
      scope = "internal" | "external";
      carrier = "...";
      vlanId = 123;
      members = [ "node-a" "node-b" ];
      endpoints = { ... };
    }

---

## What This Repository Is Not

- Not a deployment framework
- Not a secrets manager
- Not a runtime orchestrator
- Not a legacy migration layer

It is a compiler.

## License

MIT
