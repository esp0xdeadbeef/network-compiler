# Phase 1 — Stop the bleeding (separate meaning from wiring)

### 1. Freeze routing semantics

*  No new features
    
*  No new invariants
    
*  Only refactors that remove coupling
    

Goal: prevent moving targets while restructuring.

* * *

### 2. Remove VLANs from the semantic model

Search and delete VLAN meaning from anything before rendering:

*  `topology-gen` must not output `vlanId`
    
*  routing must not read `vlanId`
    
*  invariants must not mention vlan ranges
    
*  policy logic must not depend on vlan numbers
    

Replace with:

```
edge.class = "tenant-access" | "policy-core" | "upstream" | "overlay"
```

* * *

### 3. Introduce the semantic graph (new core structure)

Create a new internal structure:

```
semanticGraph = {
  nodes = { role, site }
  edges = { class, endpoints }
}
```

*  nodes have roles only (access/policy/core/uplink/overlay)
    
*  edges have type only
    
*  no addressing
    
*  no interfaces
    
*  no vlans
    

Routing must run ONLY on this.

* * *

### 4. Make routing consume semantic graph only

Refactor compile stage:

*  routing-gen reads semanticGraph
    
*  routing outputs forwarding tables
    
*  no transport assumptions
    
*  delete link-kind branching from routing
    

Goal: routing depends on **roles**, never realization.

* * *

# Phase 2 — Reintroduce the physical world (cleanly)

### 5. Add link materialization stage

New stage after routing:

```
semantic edges → concrete links
```

Implement:

*  tenant-access → adjacency
    
*  policy-core → adjacency
    
*  upstream → adjacency
    
*  overlay → adjacency
    

Still NO vlan numbers yet.

* * *

### 6. Add resource allocator

Now introduce encoding:

*  vlan allocator
    
*  subnet allocator
    
*  interface naming
    

This stage assigns:

```
link → vlanId
link → addresses
node → interface names
```

Routing must not change if allocator changes.

* * *

### 7. Rendering reads only materialized graph

Renderer should consume:

```
materializedGraph
```

Not topology.  
Not routing logic.  
Not intent.

* * *

# Phase 3 — Clean invariants

### 8. Rewrite invariants against forwarding graph

For each invariant:

*  express only as forwarding property
    
*  remove architecture words (core dumb, planes, etc)
    
*  verify using next-hop chains
    

You should end up with ~10–15 small validators.

* * *

### 9. Add invariant test harness

*  each invariant = single file
    
*  no giant validator
    
*  failing invariant prints minimal path
    

* * *

# Phase 4 — Stabilize the compiler

### 10. Delete legacy assumptions

Remove from codebase:

*  vlan ranges meaning
    
*  special router names
    
*  topology shortcuts
    
*  implicit defaults
    

If behavior depends on naming → bug.

* * *

### 11. Add alternative topology tests

Prove generality:

*  site without overlay
    
*  site with 2 uplinks
    
*  isolated tenant
    
*  transit-only site
    

Compiler must work unchanged.

* * *

# Phase 5 — Only now add features again

After all above:

*  multi-policy per site
    
*  different transports
    
*  optional authority types
    

* * *

# Sanity rule (pin this somewhere)

> Routing correctness must survive changing VLAN numbering.

If changing VLAN allocation breaks routing → architecture regressed.
