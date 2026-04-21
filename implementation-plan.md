# Implementation Plan

Goal: make the compiler the first explicit S88 boundary and keep every downstream repo consuming one canonical staged contract instead of reinterpreting intent.

## Current S88 posture

The README already describes the right architecture:

- canonical stage order is fixed
- intent is semantic, not platform-shaped
- overlays are part of intent
- realization belongs downstream

The remaining problem is not the philosophy. It is contract sharpness. Downstream repos still rely on a few shape assumptions and compatibility shims that should be made explicit here.

## Main gaps

1. Overlay output shape is not documented tightly enough.
   - Tests and downstream code can still disagree about whether overlay data lives under `transport.overlays`, `transportOverlaySpecs`, or normalized site-level structures.

2. Stage-output schemas are still implicit.
   - The compiler produces the right semantics, but the exact output contract is not described as a stable S88 artifact map.

3. Renderer-relevant identity is present but not formalized.
   - Stable names for overlays, externals, services, relations, and stage nodes should be treated as part of the contract, not as “whatever current downstream code happens to use”.

4. Intent/inventory separation is described, but the compiler README still leaves too much room for readers to assume platform hints belong here.

## Work items

1. Add an explicit schema section to `README.md`.
   - Document the normalized output shape per site.
   - Call out overlays, services, relations, tenant prefixes, stage nodes, uplinks, and provenance.
   - State which fields are normative for downstream stages.

2. Freeze the compiler-side overlay contract.
   - Choose one normalized location and shape for overlay semantics.
   - Document `name`, `peerSite`, `terminateOn`, and `mustTraverse` as compiler-owned semantic output.
   - Remove or clearly mark any legacy aliases.

3. Add contract tests for exported structures.
   - Add focused tests for:
     - multi-site overlays
     - multi-uplink external selectors
     - service targets on WAN-facing relations
     - stable node and relation identities

4. Make S88 boundary language harder.
   - Explicitly say the compiler never emits renderer hints, host mappings, bridge names, container names, or platform routing mode.

5. Add a “downstream guarantees” section.
   - Define what forwarding-model may rely on without re-normalizing compiler intent.

## Exit criteria

- A reader can tell from the README exactly what the compiler exports.
- Overlay semantics are unambiguous and appear in one canonical normalized shape.
- Forwarding-model tests do not need compiler-shape guesswork.
- No downstream repo needs to infer missing semantic identity that should have been frozen here.

## Test impact

- Keep `tests/check.sh` as the broad gate.
- Add one dedicated cross-site overlay contract test and keep it pinned.
- Add at least one golden-shape assertion for the normalized site output.
