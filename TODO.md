### TODO — Validate external reachability

The compiler must validate that every Site defines a `communicationContract`.

Additionally, ensure that at least one relation exists that allows traffic from an internal subject (e.g. tenant or tenant-set) to an external network (e.g. `wan`) with `action = "allow"`.

Purpose:

- Prevent generating fabrics where tenants have no defined external reachability.
- Catch incomplete communication contracts early in the compiler phase.



