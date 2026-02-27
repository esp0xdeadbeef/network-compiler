<!-- ./TODO.md -->
# Required for Production Readiness

This TODO reflects **current implementation status** in `lib/` as of the latest verified test run.

---

## 5. Structural Integrity (Mandatory)

- [ ] Structured error model (no raw `throw "string"`), e.g. `{ code, site, path, message, hints }`

---

## 6. Developer Ergonomics (Strongly Recommended)

- [ ] Add `nix run .#check` to CI
- [ ] Add `nix run .#compile-all-examples` (or keep `./compile-all-examples.sh`) and run it in CI
- [ ] Add “How to debug a failing invariant” section to README (point to `dev/debug.sh`, `dev/ctx-debug.sh`)
