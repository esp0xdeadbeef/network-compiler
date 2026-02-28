# TODO

- [ ] overlays require explicit policy rules in inputs.nix
- [ ] compiler MUST NOT assume policy traversal implicitly
- [ ] remove implicit `mustTraverse = ["policy"]` defaults
- [ ] fail compilation if overlay exists without matching policy definition
- [ ] validate overlay traffic is allowed via `communicationContract.allowedRelations`
- [ ] add negative test: overlay defined but no policy rules → fail
- [ ] ensure east↔west communication is explicitly declared by policy, never inferred
