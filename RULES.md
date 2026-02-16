
# Access isolation
```
for all tenantA, tenantB:
  tenantA != tenantB -> not reachable(accessRouter(tenantA), accessRouter(tenantB)) without policyRouter
```


# Core is transport only
```
for all route:
  coreRouter forwards(route) -> routingDecisionMadeBy(policyRouter, route)
```


# Policy is the only authority
```
exists exactly one policyRouter:
  for all routingDecision:
    madeBy(policyRouter, routingDecision)
```


# One policy-core link per upstream
```
for all upstreamConnection:
  exists policyCoreLink(upstreamConnection)
```


# Default route correctness
```
for all node:
  defaultRoute(node) -> reachable(node, policyRouter)
```


# Multi-site independence
```
for all site:
  routingBehavior(site) independent_of otherSites
```


