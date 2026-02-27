The cores and access routers MUST have 1 or MORE containers / vrfs, they are ALWAYS isolated and s-router-polciy can decide their access.
E.G.:
Core and access routers must have their per-adjacency local IPs (including multiple WAN links) explicitly allocated from the declared address pools and emitted as part of the compiler’s semantic contract, not inferred later by the solver.



Add just 5 tests:

NAT ingress without custom core → fail

exposed service without ingress → fail

allocator exhaustion → fail

duplicate rule priority ordering stability

schemaVersion assertion
