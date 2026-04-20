# TODO

## Policy-Driven Dedicated Transit Links ("L2 Lanes")

Status: implemented downstream (forwarding-model derives lanes; CPM binds strictly via inventory).

The compiler stays lane-agnostic on purpose:

- It defines the canonical staged architecture and explicit communication semantics.
- It does not decide whether lanes are realized as VLAN trunks, subifs, dedicated links, etc.
- It does not emit multiple parallel transit links itself; the forwarding-model derives those from compiler intent.

Remaining work:

- Keep tightening the compiler-side input contract so lane derivation stays deterministic:
  - ensure external/uplink selectors are explicit (`to.kind="external"`, use `uplinks = [ ... ]` for real uplinks)
  - ensure allow/deny relations reference existing tenants/uplinks/services
  - keep uplink naming unambiguous (unique uplink names across cores when required)
