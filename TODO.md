# TODO

## Fix external subjects in relations

**Problem**

Relations using an external subject:

```
from = { kind = "external"; name = "wan"; }
```

are compiled incorrectly into:

```
from = { kind = "tenant-set"; members = [ ] }
```

This makes the rule match **no traffic**, silently dropping WAN ingress rules.

Example broken output:

```
{
  "action": "allow",
  "from": { "kind": "tenant-set", "members": [] },
  "to": { "kind": "service", "name": "jump-host" },
  "trafficType": "ssh"
}
```

Correct output must preserve the external subject:

```
{
  "action": "allow",
  "from": { "kind": "external", "name": "wan" },
  "to": { "kind": "service", "name": "jump-host" },
  "trafficType": "ssh"
}
```

---

## Cause

`relations.from` is normalized with `normalizeTenantSubject`, which only supports:

```
tenant
tenant-set
```

But `from` may also be:

```
external
```

---

## Fix

Add subject normalization supporting:

```
tenant
tenant-set
external
```

External subjects must validate that the referenced external exists in:

```
uplinkNames ++ overlayNames
```

---

## Files affected

```
lib/correctness/policy.nix
lib/stages/build-model.nix
```

Key functions:

```
normalizeRelationWithProvenance
normalizeTenantSubject
```

---

## Acceptance

Input:

```
{
  from = { kind = "external"; name = "wan"; };
  to = { kind = "service"; name = "jump-host"; };
  trafficType = "ssh";
  action = "allow";
}
```

Output must contain:

```
"from": { "kind": "external", "name": "wan" }
```

and **must not** produce an empty tenant-set.

---

## Test

Add regression test for:

```
external -> service
external -> tenant
```

Examples:

```
allow-wan-to-jump-host
allow-wan-to-admin-web
```

---

## Priority

**High — breaks WAN ingress policies.**

