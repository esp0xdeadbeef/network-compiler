# TODO Addendum — External Routing Model Invariants

## Compiler invariants

The compiler validates only structural correctness of the model.

- Every node with role "core" must define at least one uplink.
- Each uplink must contain valid IPv4 and/or IPv6 CIDR prefixes.
- Uplink names are opaque identifiers and must not imply routing semantics.
- The compiler must not interpret prefix meaning (for example /0 vs /24).
- The compiler must not generate or infer routes.
- The compiler must not introduce implicit defaults or fallback behavior.

The compiler's responsibility ends at producing normalized solver input.


## Solver invariants

The solver owns all routing semantics.

- The solver builds upstream routing from declared uplink prefixes.
- The solver performs longest-prefix-match routing across uplinks.
- Prefixes such as 0.0.0.0/0 or ::/0 are treated as normal prefixes and not as special defaults.
- The solver must never assume that a "default uplink" exists.
- The solver must emit explicit routing state derived from uplink prefixes.
- The solver must not introduce implicit upstreams or synthesized default routes.
- The solver must ensure deterministic routing resolution when multiple uplinks exist.


## Policy interaction

Policy controls which external uplinks traffic may use.

- Policy rules referencing external destinations must reference explicit uplink names.
- The keyword "default" must not be used for external routing.
- Policy must not rely on implicit external paths.
- The solver must enforce policy independently from routing resolution.


## Removed concepts (must not be reintroduced)

The following legacy concepts are intentionally removed from the architecture.

- implicit "default" uplink
- policy flags that imply automatic default routing
- compiler-generated default routes
- solver assumptions about a primary external uplink
- implicit multi-WAN behavior

All external connectivity must be derived solely from explicitly declared uplinks and their prefixes.


## Architectural contract

- The compiler defines structure.
- The solver derives routing behavior.
- Policy restricts allowed communication paths.

No component may introduce implicit defaults or hidden routing semantics.
