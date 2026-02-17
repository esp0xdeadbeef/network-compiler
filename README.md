# Network Compiler Architecture (S88-style, human readable)

This document defines how the network compiler is structured.

It does NOT describe Linux configuration.
It describes the logic that produces it.

The goal:
A single input model produces deterministic routing behavior for every node.

---

# 1. Core Rule

The compiler builds a **site routing system first**.

Individual routers do not define the network.
Routers implement the network.

So the flow is:

```
inputs → site model → verified behavior → per-node configs
```

NOT:

```
inputs → per-node configs that hopefully work together
```

---

# 2. Structural Levels

We use simplified ISA-88 levels only as responsibility boundaries.

## Enterprise

Container for everything.

Example:

```
esp0xdeadbeef-fabric
```

Has no logic. Only groups sites.

---

## Site

A routing domain.

Examples:

```
site-a
site-b
laptop
lab
```

A site is a failure boundary and an addressing scope.

Nothing outside a site is trusted unless explicitly allowed.

---

## Process Cell (the important level)

The complete routing system of a site.

It includes:

* access routers
* policy router
* core router
* uplinks
* overlays

Think of this as:

> the network behavior of the site

This is what the compiler actually builds and verifies.

---

## Unit (a machine)

A physical or virtual host.

Examples:

```
site-a-s-router-core
site-a-s-router-policy-only
site-a-s-router-access-10
laptop
backup-host
```

A unit implements part of the site routing system.

Units do not decide policy — they execute it.

---

## Equipment Modules (capabilities inside a unit)

These describe what a node *does*, not what it is.

Examples:

| Module            | Meaning                              |
| ----------------- | ------------------------------------ |
| access-gateway    | provides a local network             |
| policy-engine     | enforces traffic rules               |
| transit-forwarder | forwards traffic but does not decide |
| wan-uplink        | connects to ISP                      |
| overlay-peer      | connects sites together              |

A unit can have multiple modules.

---

## Control Modules (actual OS configuration)

These are generated outputs:

* networkd interfaces
* routes
* nftables rules
* sysctl flags

These are never written manually.

---

# 3. Compiler Phases

The compiler runs these steps in order.

Each phase must succeed before continuing.

---

## Phase 1 — Input Validation

Input files must define:

* sites
* nodes
* roles
* allowed reachability

No routing behavior is guessed.

If ambiguous → compilation fails.

Output:
Validated intent model

---

## Phase 2 — Build Site Routing Graph

Create a logical routing graph per site:

* nodes
* connections
* authorities
* allowed directions

No IP addresses yet.

This defines *how traffic is allowed to move*.

Output:
Site routing model

---

## Phase 3 — Address Allocation

Assign deterministic IPv4 and IPv6.

Rules:

* stable across rebuilds
* extendable without renumbering
* based on identity, not interface names

Addresses exist to implement the model, not define it.

Output:
Addressed routing model

---

## Phase 4 — Policy Compilation

Convert intent into enforceable behavior:

* who may talk to whom
* default exits
* overlay routing
* packet marks
* routing tables

This produces the truth of the network.

Output:
Verified routing behavior

---

## Phase 5 — Rendering Per Node

Each unit extracts only what it must enforce.

Generate:

* networkd config
* nftables rules
* sysctls

Nodes do not need global knowledge.

Output:
Host configuration artifacts

---

# 4. Behavioral Guarantees

The compiler must be able to prove:

* tenants cannot bypass policy
* core does not become a routing authority
* overlays do not leak default routes
* each prefix has one authority
* internet reachability follows declared intent

If these cannot be proven → compilation fails.

---

# 5. What Is NOT Part of the Model

The following are implementation details and must not affect routing logic:

* VLAN numbers
* interface names
* Linux device ordering
* kernel routing quirks

Changing them must not change behavior.


These are part of the Physical model.
