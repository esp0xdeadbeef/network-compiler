
## Goal

Produce fully explicit, render-complete runtime model.

---

## 1. Canonical interfaces

* [ ] Emit effectiveRuntimeRealization.interfaces

Each interface MUST include:

* [ ] runtimeIfName

* [ ] renderedIfName

* [ ] exactly one of: link | attachment

* [ ] addr4

* [ ] addr6

* [ ] routes

* [ ] FAIL if anything missing

---

## 2. Remove legacy model

Create cleanup step:

```
rm <old files (cleanup, just like this, no need to explicitly state the filenames)>
```

* [ ] Remove runtimePorts
* [ ] Remove portMatches
* [ ] Remove any port→interface logic

---

## 3. Render completeness

* [ ] All data must live in:
  effectiveRuntimeRealization.interfaces

* [ ] Renderer must NOT:

  * infer
  * join
  * fallback

---

## 4. Determinism

* [ ] renderedIfName unique per node
* [ ] stable across runs

---

## 5. Connectivity

* [ ] No orphan interfaces
* [ ] All links valid and resolved

---

## 6. Tests

* [ ] Missing field → FAIL
* [ ] Duplicate names → FAIL
* [ ] Invalid connectivity → FAIL

---

## Done when

* Renderer is pure projection (no logic)
* Model requires zero guessing

