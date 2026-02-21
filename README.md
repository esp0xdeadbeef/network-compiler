# Structural Levels

The architecture follows ISA-88 responsibility layers.

Each layer answers a different question about the network.  
The repositories implement different layers.

The boundary is strict:

> The compiler defines communication semantics.  
> The solver realizes those semantics into an executable fabric.

* * *

## Enterprise — multi-site grouping

**Responsibility: nixos-network-compiler**

The Enterprise groups multiple independent Sites into a shared administrative domain.

Example:

Codecorp  
homelab  
customer-a

It answers:

> Which Sites belong to the same authority domain?

This layer exists to allow large or multi-organization deployments to share the same model without redesign.  
Single-site setups may use a single implicit Enterprise.

* * *

## Site — authority boundary

**Responsibility: nixos-network-compiler**

A Site defines ownership and trust scope.

Examples:

Codesite-a  
site-b  
lab  
laptop

It answers:

> Which address space is governed by the same authority?

Comparable to a routing domain or administrative domain.

The Site defines where communication rules apply.  
It does not define how traffic flows between devices.

* * *

## Process Cell — communication behavior

**Responsibility: nixos-network-compiler**

The Process Cell defines allowed communication inside a Site.

It describes:

* reachable domains
    
* enforcement requirements
    
* external reachability requirements
    
* authority roles
    
* communication permissions
    

It answers:

> What communication is valid?

No topology exists at this layer.  
No adjacency exists at this layer.  
No addressing for links exists at this layer.

The Process Cell is a behavioral contract.

Without this layer, the network contains configuration but no defined meaning.

* * *

## Unit — execution context

**Responsibility: shared**

_Declared by:_ nixos-network-compiler  
_Used by:_ nixos-fabric-solver

A Unit is a runtime execution context capable of hosting responsibilities.

Examples:

Codepolicy instance  
access instance  
transit instance

It answers:

> Where may responsibilities execute?

The compiler declares available Units.  
The solver decides how responsibilities are distributed across them.

A Unit is not a topology node and does not imply connectivity.

* * *

## Equipment Modules — responsibilities

**Derived by: nixos-fabric-solver**

Equipment Modules represent operational responsibilities required by the Process Cell.

Examples:

| Module | Meaning |
| --- | --- |
| access-gateway | terminates owned address domains |
| policy-engine | enforces communication permissions |
| transit-forwarder | carries traffic between responsibilities |
| upstream-selector | provides external reachability |
| authority-rib | owns routing decisions |

They answer:

> Which responsibilities must exist for the Site to function?

The compiler does not assign these.  
The solver derives them from the Process Cell and assigns them to Units.

* * *

## Unit Connectivity — operational relationships

**Responsibility: nixos-fabric-solver**

The solver determines how Units must relate so responsibilities can interact.

This includes:

* adjacency relationships
    
* forwarding relationships
    
* responsibility ordering
    

It answers:

> How must responsibilities interact so behavior is realizable?

This is the first layer where traffic traversal exists.

* * *

## Control Modules — execution mechanisms

**Prepared by: nixos-fabric-solver  
Implemented by: platform renderers**

Control Modules are executable configuration primitives.

Examples:

* interface addressing
    
* forwarding state
    
* route entries
    
* enforcement attachment points
    

They answer:

> What configuration must exist for a Unit to execute its responsibilities?

Control Modules remain platform-neutral until rendered.

* * *

## Platform Implementation

**Responsibility: renderer (e.g. NixOS module)**

Platform renderers translate Control Modules into device configuration.

Examples:

* systemd-networkd configuration
    
* nftables hooks
    
* routing configuration
    

They answer:

> How does a specific system express the Control Modules?

Different platforms implement the same Control Modules differently while preserving behavior.

* * *

# Responsibility Summary

| Layer | Implemented by |
| --- | --- |
| Enterprise | nixos-network-compiler |
| Site | nixos-network-compiler |
| Process Cell | nixos-network-compiler |
| Unit declaration | nixos-network-compiler |
| Equipment Modules | nixos-fabric-solver |
| Unit Connectivity | nixos-fabric-solver |
| Control Modules | nixos-fabric-solver |
| Platform configuration | renderer (e.g. NixOS) |

* * *

# Conceptual Flow

Codecompiler → semantics  
solver   → realization  
renderer → execution

