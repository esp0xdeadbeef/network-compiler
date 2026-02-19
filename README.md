# Structural Levels

The compiler follows ISA-88 responsibility layers.  
Not every deployment must use all layers.

This implementation does not currently use the Enterprise level, but the model intentionally keeps it so larger deployments can extend without redesign.

No level is “more important” than another — each level answers a different question.

* * *

## Enterprise — multi-site grouping _(optional in this implementation)_

The Enterprise groups multiple independent sites.

Example:

```
corp
homelab
customer-a
```

It answers:

> Which sites belong to the same administrative domain?

This layer is not required for single-operator setups and is unused in this project, but the architecture supports it so multiple organizations or large infrastructures can share the same compiler model without redesign.

* * *

## Site — authority boundary

A site defines ownership and trust scope.

Examples:

```
site-a
site-b
lab
laptop
```

It answers:

> Which routing domain owns these addresses?

Comparable to an autonomous routing domain.

Without a site, authority cannot be determined.

* * *

## Process Cell — routing behavior

The process cell describes the allowed forwarding behavior of the entire site:

* access reachability
    
* policy enforcement
    
* transit behavior
    
* overlays
    
* external reachability
    

It answers:

> What traffic is allowed to move where?

No devices exist yet.  
No interfaces exist yet.  
Only allowed behavior exists.

Without this layer, the network has hardware but no rules.

* * *

## Unit — execution context

A unit is an instance that executes part of the site behavior.

Examples:

```
core router instance
policy router instance
access router instance
```

It answers:

> Where is this behavior executed?

It is not necessarily a physical host — it is a runtime instance.

Without units, behavior has nowhere to run.

* * *

## Equipment Modules — capabilities

Modules describe **what a unit can do**, not what it is.

| Module | Meaning |
| --- | --- |
| access-gateway | provides subnet |
| policy-engine | enforces communication rules |
| transit-forwarder | forwards only |
| upstream-provider | exports default route |
| overlay-peer | connects sites |

They answer:

> What responsibility does this unit perform?

Without modules, units exist but have no semantics.

* * *

## Control Modules — implementation mechanisms

These are generated operating system artifacts that realize compiled behavior.

They do not define behavior — they enforce it.

Examples:

* interfaces
    
* routes
    
* nftables rules
    
* sysctls

* DNS (e.g. unbound, bind)
    
* DHCP servers (e.g. Kea)
    
* Router advertisements (e.g. radvd)
    
* uplink mechanisms (e.g. PPP, DHCP client)
    

They answer:

> How is the behavior implemented?

Multiple mechanisms may implement the same behavior.  
Changing the mechanism must not change the routing model.

Without this layer, the system has defined behavior but cannot execute it.

