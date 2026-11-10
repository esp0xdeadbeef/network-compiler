# TODO

## Policy-Driven Dedicated Transit Links ("L2 Lanes")

Status: implemented downstream (forwarding-model derives lanes; CPM binds strictly via inventory).

The compiler stays lane-agnostic on purpose:

- It defines the canonical staged architecture and explicit communication semantics.
- It does not decide whether lanes are realized as VLAN trunks, subifs, dedicated links, etc.
- It does not emit multiple parallel transit links itself; the forwarding-model derives those from compiler intent.

Remaining work:

- Keep tightening the compiler-side input contract so lane derivation stays deterministic:
  - ensure external/uplink selectors are explicit (`to.kind="external"`, pin the exit scope with `scope = "<exit-scope>"`; `uplinks = [ ... ]` on an external selector is rejected as a superseded contract)
  - ensure allow/deny relations reference existing tenants/uplinks/services
  - keep uplink naming unambiguous (unique uplink names across cores when required)

## Stage co-location acceptance

Status: modeled, not accepted. `README.md` § Stage co-location describes it as
part of the model; the validator rejects it.

The five canonical stages are architectural, not devices, so a compact site
should be able to co-locate `downstream-selector`, `policy`,
`upstream-selector`, and `core` on one node. Today `role` is a single string and
every stage must exist as its own node, so no site with fewer than five stage
nodes can compile.

Trace handles: URS site manifest (`allowed role co-location`) and practical
deployment profiles; `../network-codex-agent/GAMP/FS` FS-650 (profile manifest,
`roleColocation`); FS-320 / `../network-codex-agent/GAMP/SDS`
FS-320-HDS-010-SDS-010 (layout preservation); `../network-codex-agent/GAMP/SMS`
FS-650-HDS-010-SDS-010-SMS-010..040.

Owning code:

- `lib/correctness/topology.nix` (stage presence checks)
- `lib/correctness/topology/stage-links.nix` (adjacency checks)
- `lib/correctness/topology/policy-traversal.nix` (stage crossing)
- `lib/stages/traffic-paths/selectors/roles.nix` (stage selection)

Invariants that must not change: `stagePath` stays
`access → downstream-selector → policy → upstream-selector → core`, and
`requiresPolicy` / `forbidsCoreToCoreP2P` keep their current meaning.

Evidence required before this can be called implemented:

- an explicit stage-occupancy contract (which stages a node serves), contiguous
  spans only
- stage-presence checks restated as coverage rather than exact-role existence
- link validation restated as gap occupancy, so a co-located pair needs no link
- policy traversal restated over stages so a collapsed node counts as crossing
- a stage-level co-location field read by the topology validator, distinct from
  the provider-role vocabulary used today (`provider-edge`,
  `public-ingress`) or explicitly mapped to it
- SMT rows that compile a one-node and a three-node site through the full
  compiler → NFM → CPM → renderer path, plus a seeded negative for each refusal
  diagnostic
