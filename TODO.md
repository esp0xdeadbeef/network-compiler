# TODO

## Policy-Driven Dedicated Transit Links ("L2 Lanes")

The compiler defines communication semantics and a canonical staged architecture, but it does not currently provide a way
to *guarantee* that policy/egress intent implies dedicated L2 separation between stages.

This is tracked as a forwarding-model feature (lane-aware p2p / multi-link), but the compiler may need to evolve to:

- document the current limitation: `topology.links` is a list of node pairs, so only one logical link per node pair is expressible.
- ensure the compiler output remains sufficient for forwarding model to derive lanes deterministically from:
  - `communicationContract.relations` (especially `to.kind="external"` / `uplinks`)
  - attachments (tenants/services)
  - overlay intent (`transport.overlays`)

Non-goal: the compiler should not decide VLAN/subif/etc realization details.
That remains a realization/inventory concern downstream.

