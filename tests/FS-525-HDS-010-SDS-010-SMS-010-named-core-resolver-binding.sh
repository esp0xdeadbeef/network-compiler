#!/usr/bin/env bash
set -euo pipefail

# GAMP-ID: FS-525-HDS-010-SDS-010-SMS-010
# GAMP-SCOPE: software-module-test

ROOT="${NETWORK_COMPILER_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
LABS="${NETWORK_LABS_PATH:-/home/deadbeef/github/network-labs}"

result="$(${NIX_BIN:-nix} eval --impure --json --expr "
  let
    compiler = builtins.getFlake (toString ${ROOT});
    lib = compiler.inputs.nixpkgs.lib;
    source = import ${LABS}/GAMP/SMT/FS-525-HDS-010-SDS-010-SMS-010/intent.nix;
    compiled = compiler.lib.compile builtins.currentSystem source;
  in compiled.sites.mini-smt.FS-525-HDS-010-SDS-010-SMS-010.dns
")"

jq -e '
  .schemaVersion == 1
  and .warnings == []
  and .recursive.services == [{
    addressAuthority: "model-allocated-service-prefix",
    name: "core-dns",
    providerNode: "core-primary",
    recursionMode: "iterative",
    trafficType: "dns"
  }]
  and (.recursive.bindings | length) == 1
  and .recursive.bindings[0].requesterScope == {kind: "service", name: "access-dns"}
  and .recursive.bindings[0].upstreamResolver == {kind: "service", name: "core-dns", node: "core-primary"}
  and .recursive.bindings[0].egressSurface == {kind: "external", uplinks: ["isp-primary"]}
  and .recursive.bindings[0].allowedAddressFamilies == ["ipv4", "ipv6"]
' <<<"$result" >/dev/null

if ! jq -e '[.warnings[]? | .. | strings | select(
  test("(^|[^0-9])([0-9]{1,3}\\.){3}[0-9]{1,3}([^0-9]|$)")
  or test("^([0-9A-Fa-f]{0,4}:){2,}[0-9A-Fa-f]{0,4}(/[0-9]+)?$")
)] == []' <<<"$result" >/dev/null; then
  echo "FAIL: DNS warnings leaked address material" >&2
  exit 1
fi

echo "PASS: FS-525 named core resolver binding is normalized without address literals or reproducibility warnings"

seeded="$(${NIX_BIN:-nix} eval --impure --json --expr "
  let
    compiler = builtins.getFlake (toString ${ROOT});
    lib = compiler.inputs.nixpkgs.lib;
    source = import ${LABS}/GAMP/SMT/FS-525-HDS-010-SDS-010-SMS-010/intent.nix;
    base = source.mini-smt.FS-525-HDS-010-SDS-010-SMS-010;
    recursive = base.recursiveDnsIntent;
    binding = builtins.head recursive.bindings;
    service = builtins.head recursive.services;
    compileWarnings = name: site:
      (compiler.lib.compile builtins.currentSystem { mini-smt = { \"\${name}\" = site; }; })
        .sites.mini-smt.\"\${name}\".dns.warnings;
    withBinding = replacement: base // {
      recursiveDnsIntent = recursive // { bindings = [ replacement ]; };
    };
    secondaryCore = {
      role = \"core\";
      uplinks.overlay-secondary-only = {
        ipv4 = [ \"0.0.0.0/0\" ];
        ipv6 = [ \"::/0\" ];
      };
    };
    ambiguous = base // {
      topology = base.topology // {
        nodes = base.topology.nodes // { core-secondary = secondaryCore; };
        links = base.topology.links ++ [ [ \"upstream-selector\" \"core-secondary\" ] ];
      };
      recursiveDnsIntent = recursive // {
        services = recursive.services ++ [ (service // { providerNode = \"core-secondary\"; }) ];
      };
    };
  in {
    missing = compileWarnings \"missing\" (withBinding (builtins.removeAttrs binding [ \"upstreamResolver\" ]));
    literal = compileWarnings \"literal\" (withBinding (binding // { upstreamResolver = \"resolver-value\"; }));
    invalid = compileWarnings \"invalid\" (withBinding (binding // {
      upstreamResolver = { kind = \"service\"; name = \"unknown-core-dns\"; node = \"unknown-core\"; };
    }));
    ambiguous = compileWarnings \"ambiguous\" ambiguous;
    hardcoded = compileWarnings \"hardcoded\" (base // {
      recursiveDnsIntent = recursive // {
        services = [ (service // { upstreamResolver = \"provider-static\"; }) ];
      };
    });
    permutedAmbiguous = compileWarnings \"permuted-ambiguous\" (ambiguous // {
      recursiveDnsIntent = ambiguous.recursiveDnsIntent // {
        services = lib.reverseList ambiguous.recursiveDnsIntent.services;
      };
    });
  }
")"

jq -e '
  ([.missing[].code] | index("DNS_CORE_BINDING_MISSING")) != null
  and ([.literal[].code] | index("DNS_CORE_BINDING_LITERAL")) != null
  and ([.invalid[].code] | index("DNS_CORE_BINDING_INVALID")) != null
  and ([.ambiguous[].code] | index("DNS_CORE_BINDING_AMBIGUOUS")) != null
  and ([.hardcoded[].code] | index("DNS_CORE_UPSTREAM_HARDCODED")) != null
  and ([.ambiguous[] | del(.site)] == [.permutedAmbiguous[] | del(.site)])
  and all(.[][];
    .disposition == "fail-closed"
    and (.candidateIds == (.candidateIds | sort | unique))
  )
' <<<"$seeded" >/dev/null

if ! jq -e '[.[][] | .. | strings | select(
  test("(^|[^0-9])([0-9]{1,3}\\.){3}[0-9]{1,3}([^0-9]|$)")
  or test("^([0-9A-Fa-f]{0,4}:){2,}[0-9A-Fa-f]{0,4}(/[0-9]+)?$")
)] == []' <<<"$seeded" >/dev/null; then
  echo "FAIL: seeded DNS warnings leaked address material" >&2
  exit 1
fi

echo "PASS: FS-525 seeded warning profiles are deterministic, privacy-safe, and fail closed"
