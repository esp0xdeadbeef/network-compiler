# nixos-network-compiler

A deterministic compiler that converts **network intent** into a **platform-independent, staged network model**.

The compiler does **not** generate vendor or device configuration.
Instead, it produces a stable intermediate representation that later stages can realize and render.

This project is intentionally **opinionated**.
It does not attempt to preserve arbitrary topology as-is.
Instead, it normalizes supported intent into a fixed staged forwarding architecture with explicit authority boundaries.

Canonical traversal order:

```text
access → downstream-selector → policy → upstream-selector → core
```

That staged architecture is part of the model.
It is not incidental.

Smaller deployments may **co-locate multiple stages on the same realized node**, but the canonical model and traversal order remain the same.

---

# Disclaimer

This project exists primarily to support my own infrastructure.

If it happens to be useful to others, great — but **pin a specific version**.
The internal schema may change between versions.
Backward compatibility is **not guaranteed**.

Pull requests are welcome, but changes that conflict with the architectural model are unlikely to be merged.

This repository is not trying to be a universal network compiler for every possible topology style.
It is an **infrastructure-first, architecture-first compiler** for a specific staged fabric model.

---

# Reality check

If your goal is simply:

```text
site-a ↔ site-b
```

over a tunnel, this project is **completely unnecessary**.

You could solve that with something as small as:

```bash
ip route add 10.20.0.0/24 via 10.0.0.2 dev wg0
```

Done.

This repository exists because I chose to build something **much more complicated** instead.

In other words:

> This project is occasionally a **nuclear reactor used to boil water**.

The goal is not just connectivity.
The goal is:

* deterministic topology construction
* explicit forwarding authority boundaries
* stable staged traversal
* reproducible addressing
* policy placement discipline
* renderer-independent intermediate output

Once a network needs those things, the simple solutions stop scaling quickly.

So yes — for two sites and a tunnel, this is overkill.
But once the network stops being trivial, the structure starts to make sense.

---

# Project intent

This project intentionally enforces **one canonical network architecture**.

That is not an accident.
That is the whole point.

A small network should be able to grow into:

* multi-core
* multi-wan
* multi-site
* multi-enterprise

without requiring a different compiler model or a rewritten codebase.

The way this project achieves that is by enforcing a fixed staged architecture up front.
The topology may grow.
The scale may grow.
The realization may become more distributed.
But the model stays the same.

This means:

* the compiler has fewer ambiguous cases
* later stages have stable assumptions
* authority boundaries remain explicit
* growth happens by changing data, not by replacing the model

---

# What this project does

The compiler converts a **high-level network description** into a deterministic **staged network model**.

Input describes things like:

* enterprises
* sites
* tenants
* services
* communication policy
* topology intent
* address pools
* overlays
* uplinks

Output describes things like:

* normalized staged topology
* deterministic addressing
* communication contracts
* attachment relationships
* routing domains
* stage participation
* traversal ordering
* authority boundaries

The result is a **platform-independent description of a network site**, constrained to the canonical fabric architecture.

Later stages can turn this into:

* router configuration
* firewall rules
* containerlab labs
* NixOS modules
* simulation environments
* other renderer-specific outputs

---

# What this project does not do

This compiler does **not**:

* generate vendor configuration
* choose routing protocols
* decide BGP vs OSPF vs static routing
* emit nftables rules
* emit Cisco ACLs
* emit Junos policy statements
* decide how a renderer collapses co-located stages on a target platform

Those decisions belong to later stages.

The compiler defines the **canonical model**.
Other stages decide how to realize that model.

---

# Position in the architecture

This repository is part of a multi-stage pipeline.

| Layer                   | Responsibility                                                                |
| ----------------------- | ----------------------------------------------------------------------------- |
| **Compiler**            | defines communication semantics and canonical staged topology                 |
| **Forwarding model**    | constructs deterministic forwarding structure from the canonical staged model |
| **Control plane model** | derives control-plane mechanisms and realization inputs                       |
| **Renderer**            | emits platform-specific configuration                                         |

Pipeline:

```text
intent
  ↓
compiler
  ↓
forwarding model
  ↓
control plane model
  ↓
renderer
```

This repository implements the **compiler stage**.

---

# Architectural stance

The compiler is **platform-independent**, but it is **not topology-neutral**.

That distinction matters.

The compiler does not try to preserve arbitrary user topology as a free-form graph all the way down.
Instead, it normalizes supported intent into a fixed staged forwarding architecture:

```text
access → downstream-selector → policy → upstream-selector → core
```

That means this project is opinionated in two ways:

1. It preserves **architectural determinism** over topology freedom.
2. It requires later stages to realize the canonical staged model, not invent their own forwarding architecture.

If a renderer wants to collapse multiple stages onto one device, that is fine.
If a renderer wants to map the model to VRFs, route leaking, firewall zones, logical systems, containers, namespaces, or some other mechanism, that is also fine.

But the renderer does **not** get to change the compiler’s stage order or authority model.

---

# Canonical fabric stages

The compiler works with five canonical forwarding stages:

| Stage                 | Responsibility                                                           |
| --------------------- | ------------------------------------------------------------------------ |
| `access`              | tenant attachment and access-edge entry                                  |
| `downstream-selector` | downstream path selection / staged aggregation before enforcement        |
| `policy`              | policy enforcement and contract-controlled traversal                     |
| `upstream-selector`   | upstream path selection toward exit-capable core                         |
| `core`                | exit anchoring, external connectivity, and top-level transport anchoring |

These are **canonical stages**, not necessarily five distinct devices.

A realization may:

* place one stage on one node
* place multiple stages on one node
* split one stage family across multiple nodes where the architecture permits it

But the model always preserves the same stage semantics and traversal order.

---

# Stage co-location

A small site does **not** need five separate boxes to fit this model.

What it needs is five **architectural stages**.

Those stages may be co-located.
For example:

* a compact deployment may co-locate `downstream-selector`, `policy`, `upstream-selector`, and `core` on one realized node
* a larger deployment may split them across multiple realized nodes
* an even larger deployment may replicate selected stages where the model allows it

The important invariant is not “always five boxes.”
The important invariant is:

> every supported site compiles into the same staged forwarding architecture.

This is what allows a small deployment to grow into a larger one without changing the compiler model.

---

# Why the staged model is enforced

The staged architecture exists to remove ambiguity.

Without a canonical architecture, the compiler and downstream stages tend to accumulate ambiguity around:

* traversal order
* forwarding responsibility
* policy placement
* upstream / downstream choice
* route propagation boundaries
* exit ownership
* renderer fallback behavior

The staged model avoids that by making authority boundaries explicit.

This project therefore prefers:

* a single opinionated architecture
* deterministic normalization
* stable stage ordering
* explicit stage responsibilities

over:

* arbitrary graph freedom
* topology-specific special cases
* per-scenario model variants
* renderer-defined policy architecture

---

# Compiler responsibilities

The compiler defines:

* what communication must be possible
* which communication is allowed or denied
* which architectural stages exist
* how topology is normalized into canonical stage order
* how addressing and ownership are made deterministic
* which boundaries later stages must preserve

The compiler does **not** decide:

* which protocol implements forwarding
* which platform feature realizes a stage boundary
* how a vendor-specific renderer encodes the result

It produces a **deterministic staged model** that later stages consume.

---

# Policy model

Network behavior is defined through a **communication contract**.

The contract describes things like:

| Component       | Purpose                                |
| --------------- | -------------------------------------- |
| `trafficTypes`  | protocol / traffic definitions         |
| `services`      | logical services provided by endpoints |
| `relations`     | allowed or denied communication        |
| `interfaceTags` | semantic labels used by later stages   |

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

This expresses **behavioral intent**, not device rules.

The compiler is responsible for preserving the meaning of the contract and attaching it to the canonical staged topology.

Later stages may translate that into:

* firewall policy
* ACLs
* service bindings
* route filters
* security zones
* other enforcement mechanisms

But the compiler itself stops at intent and staged authority.

---

# Topology model

Topology in this project describes **network execution structure inside a fixed staged architecture**.

Nodes represent forwarding units.
Links represent connectivity relationships that are later normalized into canonical traversal order.

Canonical stage order:

```text
Access → Downstream Selector → Policy → Upstream Selector → Core
```

Each stage has a defined responsibility:

| Stage                 | Meaning                                         |
| --------------------- | ----------------------------------------------- |
| `access`              | tenant-facing attachment point                  |
| `downstream-selector` | staged distribution / downstream path choice    |
| `policy`              | communication enforcement point                 |
| `upstream-selector`   | upstream path choice toward exit-capable fabric |
| `core`                | external anchoring and transport exit           |

The compiler validates topology against this architectural model.

Examples of enforced properties include:

* no disconnected staged topology
* valid canonical traversal order
* explicit stage presence where required
* deterministic link ordering
* no ambiguous authority ownership

---

# Deterministic guarantees

For a given input, the compiler always produces the same output.

The resulting model guarantees:

* deterministic address allocation
* stable topology ordering
* explicit authority boundaries
* validated policy structure
* canonical staged traversal
* platform-independent intermediate output

The output is intended for **further compilation stages**, not for direct device deployment.

---

# Genericity model

This project is **generic across realizations**, not generic across arbitrary architectural styles.

That means:

* the intermediate model is platform-independent
* different renderers may realize the same staged model differently
* the same canonical architecture may be realized on NixOS, Cisco, Juniper, labs, or simulation systems

But it does **not** mean:

* every possible network architecture is accepted as-is
* renderers are free to invent a different stage model
* topology remains unconstrained by the compiler

The genericity boundary is therefore:

> one canonical staged fabric model, many possible realizations.

---

# Growth model

A site should be able to grow without changing the compiler model.

Examples:

* single-core to multi-core
* single-wan to multi-wan
* single-site to multi-site
* single-enterprise to multi-enterprise

This project treats those as **data growth problems**, not model replacement problems.

The canonical staged architecture remains the same.
Only the scope, cardinality, and realization change.

That is one of the primary reasons the model is intentionally rigid.

---

# Why this exists (design goals)

This toolchain exists because I want all of the following at the same time:

* **S88-style separation** (clear responsibility boundaries between stages)
* **Deterministic IPv4/IPv6 layouts** (predictable addressing and stable identities)
* **Explicit containment** (a rogue uplink/core must not affect other uplinks or bypass policy)
* **Overlays evaluated by policy** (e.g. NAS backup over an overlay that must traverse policy)
* **Intent distilled from configuration** (high-level `intent.nix`, separate realization/inventory)
* **Scale without rewriting layers** (single-wan → multi-wan → multi-enterprise without changing the pipeline)
* **Protocol plurality downstream** (static/BGP/other routing protocols derived from deterministic model output)

If you only need “two sites over a tunnel”, none of this is worth it.

---

# Current limitation (important)

The compiler validates staged topology and policy structure, but it does **not** (yet) guarantee *policy-driven dedicated L2 separation*.

`topology.links` expresses stage adjacency as node pairs, and downstream stages currently assume “one p2p link per node pair”.
That means `intent.nix` cannot yet express “dedicated lanes” whose existence is derived from policy/egress intent.

The planned direction is to derive dedicated “L2 lanes” in the forwarding-model stage and bind them via inventory in the control-plane-model stage.
See `network-forwarding-model/TODO.md` (in that repo) for the lane-aware p2p plan.

---

# Platform independence

The compiler output is designed to be platform-independent.

That means the output should describe things like:

* staged topology
* communication semantics
* ownership
* attachment relationships
* routing domains
* canonical traversal expectations

It should not depend on:

* Linux namespaces
* NixOS options
* nftables syntax
* Cisco CLI syntax
* Junos stanza layout
* container-specific implementation details

Platform-specific realization belongs downstream.

---

# Example output structure

The compiler produces structured data that later stages consume.

A typical output includes things like:

```text
enterprise
 └ site
    ├ communicationContract
    ├ domains
    ├ attachments
    ├ stagedTopology
    ├ addressPools
    ├ ownership
    ├ uplinks
    └ transit
```

This output becomes the **input to the forwarding model stage**.

The exact internal schema may evolve.
Pin versions if you depend on it.

---

# Running the compiler

Compile a site definition (local fixture):

```bash
nix run .#compile -- tests/fixtures/single-uplink.nix
```

Compile an example from `network-labs` (via the flake input):

```bash
nix run .#compile -- labs:examples/single-wan/intent.nix
```

Compile all examples:

```bash
./compile-all-examples.sh
```

Debug compilation:

```bash
nix run .#debug -- tests/fixtures/single-uplink.nix
```

---

# Tests

Run the test suite:

```bash
nix run .#check
```

The test suite includes:

* positive examples
* negative validation tests
* regression tests
* staged topology checks
* deterministic output checks

---

# Architectural invariant

The system maintains one directional rule:

```text
behavior
  → staged forwarding structure
  → realization inputs
  → platform configuration
```

Each stage reduces ambiguity without pushing architectural responsibility into later stages.

The renderer is allowed to **realize** the architecture.
It is not allowed to **invent** it.

---

# ISA-88 interpretation

The architecture loosely follows ISA-88 style responsibility separation.

| ISA-88           | Meaning here                        |
| ---------------- | ----------------------------------- |
| Enterprise       | administrative grouping             |
| Site             | authority boundary                  |
| Process Cell     | allowed communication behavior      |
| Unit             | forwarding execution context        |
| Equipment Module | responsibility of a forwarding unit |
| Control Module   | implementation mechanism            |

This compiler stops at the stage where communication behavior and staged architectural boundaries are made explicit.

Later stages realize those semantics into operational networks.

---

# Non-goals

This project is not trying to be:

* a universal topology-preserving graph compiler
* a vendor-native configuration generator
* a compatibility layer for every network architecture style
* a magic abstraction that removes the cost of realization

It is trying to be:

* deterministic
* explicit
* architecture-first
* reproducible
* renderer-independent within its architectural scope

---

# Practical expectation for downstream renderers

If you write a renderer for this model, the expectation is:

* consume the canonical staged architecture
* preserve stage authority boundaries
* realize co-located stages when appropriate
* do not reorder or erase the stage model
* do not repair missing intent by inventing policy

A renderer may choose **how** to realize the model.
It may not choose **whether the model means something else**.

---

# Summary

This project is a deterministic compiler for a **fixed staged enterprise fabric model**.

It is:

* platform-independent
* architecture-opinionated
* deterministic
* intended as a compiler stage, not a final renderer

It intentionally normalizes supported network intent into the canonical traversal model:

```text
access → downstream-selector → policy → upstream-selector → core
```

That is the point.
Not a side effect.

If that architecture fits your goals, the model can scale cleanly.
If it does not, this repository is probably not the right tool.
