# network-compiler S88 Boundary

`network-compiler` owns semantic normalization from intent to a
renderer-independent staged model.

## Enterprise

Enterprise and site grouping is normalized by `lib/stages/regroup-sites.nix`
and `lib/flatten-sites.nix`.

## Site

Site compilation is owned by `lib/stages/compile-site.nix` and
`lib/stages/build-model.nix`.

## Unit

Canonical staged fabric units are derived by `lib/stages/traffic-paths.nix`,
`lib/stages/overlay-attachments.nix`, `lib/stages/normalize-uplinks.nix`, and
`lib/stages/normalize-overlays.nix`.

## ControlModule

Validation and normalization helpers live under `lib/correctness/`,
`lib/address-safety/`, `lib/allocators/`, and `lib/stages/validate-*.nix`.
They must fail before downstream stages when intent lacks required semantic
authority.

