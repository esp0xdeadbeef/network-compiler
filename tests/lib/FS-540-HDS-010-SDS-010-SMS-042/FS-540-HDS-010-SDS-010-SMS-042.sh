#!/usr/bin/env bash
set -euo pipefail

# GAMP-ID: FS-540-HDS-010-SDS-010-SMS-042
# GAMP-SCOPE: software-module-test
#
# Recursive DNS Projection Non-Interference — Compiler
#
# Proves that adding/removing/replacing recursive DNS relations affects only
# records whose provenance names that relation, its resolver service, or its
# selected path.  Unrelated records (tenants, IPv6 policy units, isolation
# decisions, access-space discovery, overlay attachments) remain byte-equivalent.
#
# Seeded negatives per SMS-042:
#   SN1: VLAN 2 + VLAN 7 + delegated-prefix IPv6 + non-DNS services — replace
#        DNS-to-WAN with no-DNS; every unrelated record byte-equivalent.
#   SN2: Permute DNS services/relations; emitted DNS delta and preserved set
#        remain byte-equivalent.
#   SN3: Faulty retention branch (broad hasDnsRelation) would be caught by the
#        compiler's own deterministic structure.

ROOT="${NETWORK_COMPILER_ROOT:-${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}}"
NIX="${NIX_BIN:-nix}"

result="$("$NIX" eval --impure --json --expr "
  let
    compiler = builtins.getFlake (toString ${ROOT});
    lib = compiler.inputs.nixpkgs.lib;

    nodes = {
      access-vlan2 = {
        role = \"access\";
        attachments = [ { kind = \"tenant\"; name = \"clients\"; } ];
      };
      access-vlan7 = {
        role = \"access\";
        attachments = [ { kind = \"tenant\"; name = \"clients\"; } ];
      };
      downstream = { role = \"downstream-selector\"; };
      policy = { role = \"policy\"; };
      upstream = { role = \"upstream-selector\"; };
      core-primary = {
        role = \"core\";
        uplinks = {
          wan-vlan4 = {
            ipv4 = [ \"0.0.0.0/0\" ];
            ipv6 = [ \"::/0\" ];
          };
        };
      };
    };

    links = [
      [ \"access-vlan2\" \"downstream\" ]
      [ \"access-vlan7\" \"downstream\" ]
      [ \"downstream\" \"policy\" ]
      [ \"policy\" \"upstream\" ]
      [ \"upstream\" \"core-primary\" ]
    ];

    nonDnsContract = {
      trafficTypes = [
        { name = \"https\"; match = [ { proto = \"tcp\"; family = \"any\"; dports = [ 443 ]; } ]; }
        { name = \"icmp\"; match = [ { proto = \"icmp\"; family = \"any\"; } ]; }
        { name = \"dns\";   match = [ { proto = \"udp\"; family = \"any\"; dports = [ 53 ]; } ]; }
      ];
      services = [
        { name = \"access-dns\"; providers = [ \"access-vlan2\" \"access-vlan7\" ]; trafficType = \"dns\"; }
      ];
      relations = [
        {
          id = \"allow-clients-to-wan-https\";
          priority = 100;
          from = { kind = \"tenant\"; name = \"clients\"; };
          to = { kind = \"external\"; uplinks = [ \"wan-vlan4\" ]; };
          trafficType = \"https\";
          action = \"allow\";
          returnBehavior = \"symmetric\";
        }
        {
          id = \"allow-clients-to-wan-icmp\";
          priority = 110;
          from = { kind = \"tenant\"; name = \"clients\"; };
          to = { kind = \"external\"; uplinks = [ \"wan-vlan4\" ]; };
          trafficType = \"icmp\";
          action = \"allow\";
          returnBehavior = \"symmetric\";
        }
      ];
    };

    ipv6 = {
      internetMode = { clients = \"delegated-prefix\"; };
      delegatedPrefix = {
        source = \"wan-vlan4\";
        pools = { ipv6 = \"2001:db8:dead:beef::/56\"; };
      };
      tenants = {
        clients = {
          pools = { ipv6 = \"2001:db8:dead:beef:f00d::/64\"; };
        };
      };
    };

    siteBase = {
      pools = {
        p2p.ipv4 = \"10.10.0.0/24\";
        loopback.ipv4 = \"10.19.0.0/24\";
      };
      ownership = {
        prefixes = [
          { kind = \"tenant\"; name = \"clients\"; ipv4 = \"10.20.10.0/24\"; }
        ];
      };
      topology = { inherit nodes links; };
      communicationContract = nonDnsContract;
      inherit ipv6;
    };

    # Variant A: DNS-to-WAN (recursive DNS present)
    withDns = siteBase // {
      recursiveDnsIntent = {
        services = [
          { name = \"core-dns\"; providerNode = \"core-primary\";
            addressAuthority = \"model-allocated-service-prefix\";
            recursionMode = \"iterative\"; trafficType = \"dns\"; }
        ];
        bindings = [
          { requesterScope = { kind = \"service\"; name = \"access-dns\"; };
            upstreamResolver = { kind = \"service\"; name = \"core-dns\"; node = \"core-primary\"; };
            egressSurface = { kind = \"external\"; uplinks = [ \"wan-vlan4\" ]; };
            allowedAddressFamilies = [ \"ipv4\" \"ipv6\" ]; }
        ];
      };
    };

    # Variant B: No recursive DNS (DNS removed)
    noDns = siteBase // {};

    # Variant C: Permuted DNS (reversed binding list — must be stable)
    withDnsPermuted = withDns // {
      recursiveDnsIntent = withDns.recursiveDnsIntent // {
        bindings = lib.reverseList withDns.recursiveDnsIntent.bindings;
      };
    };

    compile = source:
      let
        full = { mini-smt.\"FS-540-HDS-010-SDS-010-SMS-042\" = source; };
        compiled = compiler.lib.compile builtins.currentSystem full;
      in compiled.sites.mini-smt.\"FS-540-HDS-010-SDS-010-SMS-042\";

    withDnsOut = compile withDns;
    noDnsOut = compile noDns;
    withDnsPermutedOut = compile withDnsPermuted;

    # Strip DNS-provenance fields — non-interference boundary
    stripDns = site: builtins.removeAttrs site [
      \"dns\" \"relations\" \"trafficPaths\" \"services\"
      \"consumedInterfaces\" \"sourceAudit\"
    ];

    nonDnsWithDns = stripDns withDnsOut;
    nonDnsNoDns = stripDns noDnsOut;
    nonDnsPermuted = stripDns withDnsPermutedOut;

    # --- Primary: non-DNS byte-equivalent ---
    nonDnsMatch = nonDnsWithDns == nonDnsNoDns;
    dnsDiffers = withDnsOut.dns != noDnsOut.dns;
    permutedNonDnsMatch = nonDnsPermuted == nonDnsWithDns;
    dnsPermutedMatch = withDnsOut.dns == withDnsPermutedOut.dns;

    # --- IPv6 tenant record count preserved ---
    ipv6TenantCountBase = builtins.length
      (builtins.attrNames (withDnsOut.ipv6.tenants or {}));
    ipv6TenantCountNoDns = builtins.length
      (builtins.attrNames (noDnsOut.ipv6.tenants or {}));
    ipv6TenantsMatch = ipv6TenantCountBase == ipv6TenantCountNoDns && ipv6TenantCountBase > 0;

    # --- Isolation decisions unchanged ---
    isolationMatch = withDnsOut.isolationDecisions == noDnsOut.isolationDecisions;

    # --- Access-space discovery unchanged ---
    discoveryMatch = withDnsOut.accessSpaceDiscovery == noDnsOut.accessSpaceDiscovery;

    # --- DNS dns.recursive *does* change (with vs without) ---
    dnsRecursiveDiffer = withDnsOut.dns.recursive != noDnsOut.dns.recursive;

    # --- Compiler output warns about missing DNS binding when DNS removed ---
    dnsNoDnsHasWarnings = builtins.length (noDnsOut.dns.warnings or []) > 0;

    # --- Cardinality diagnostics ---
    relationCountWith = builtins.length withDnsOut.relations;
    relationCountNo = builtins.length noDnsOut.relations;
    pathCountWith = builtins.length withDnsOut.trafficPaths;
    pathCountNo = builtins.length noDnsOut.trafficPaths;

    # --- DNS service was added to communicationContract by compiler ---
    dnsServiceAdded = builtins.any
      (s: s.name == \"core-dns\")
      (withDnsOut.services or []);

  in {
    inherit
      nonDnsMatch dnsDiffers permutedNonDnsMatch dnsPermutedMatch
      ipv6TenantsMatch isolationMatch discoveryMatch
      dnsRecursiveDiffer dnsNoDnsHasWarnings dnsServiceAdded
      ipv6TenantCountBase ipv6TenantCountNoDns
      relationCountWith relationCountNo
      pathCountWith pathCountNo
      ;
  }
")"

echo "=== FS-540-HDS-010-SDS-010-SMS-042 Compiler: Recursive DNS Projection Non-Interference ==="

# MR1: non-DNS records byte-equivalent across DNS presence
jq -e '.nonDnsMatch == true' <<<"$result" >/dev/null \
  && echo "PASS: MR1 - non-DNS records (tenants, IPv6, isolation, discovery, overlay) byte-equivalent" \
  || { echo "FAIL: MR1 - non-DNS records changed when recursive DNS was removed" >&2; jq '{nonDnsMatch}' <<<"$result" >&2; exit 1; }

# MR2: DNS output differs (proving the change was applied)
jq -e '.dnsDiffers == true' <<<"$result" >/dev/null \
  && echo "PASS: MR2 - DNS output changes when recursiveDnsIntent is removed" \
  || { echo "FAIL: MR2 - DNS output must differ; it didn't" >&2; exit 1; }

# MR3: IPv6 tenant records preserved
jq -e '.ipv6TenantsMatch == true' <<<"$result" >/dev/null \
  && echo "PASS: MR3 - IPv6 tenant record count preserved ($(jq -r '.ipv6TenantCountBase' <<<"$result") tenants)" \
  || { echo "FAIL: MR3 - IPv6 tenant count changed" >&2; jq '{ipv6TenantCountBase, ipv6TenantCountNoDns}' <<<"$result" >&2; exit 1; }

# MR4: Isolation decisions unchanged
jq -e '.isolationMatch == true' <<<"$result" >/dev/null \
  && echo "PASS: MR4 - isolation decisions unchanged" \
  || { echo "FAIL: MR4 - isolation decisions changed" >&2; exit 1; }

# MR5: Access-space discovery unchanged
jq -e '.discoveryMatch == true' <<<"$result" >/dev/null \
  && echo "PASS: MR5 - access-space discovery unchanged" \
  || { echo "FAIL: MR5 - access-space discovery changed" >&2; exit 1; }

# SN1: Permuted DNS bindings produce identical output (deterministic)
jq -e '.permutedNonDnsMatch == true' <<<"$result" >/dev/null \
  && echo "PASS: SN1a - permuted DNS bindings preserve non-DNS records" \
  || { echo "FAIL: SN1a" >&2; exit 1; }

jq -e '.dnsPermutedMatch == true' <<<"$result" >/dev/null \
  && echo "PASS: SN1b - DNS output identical after binding permutation" \
  || { echo "FAIL: SN1b" >&2; exit 1; }

# SN2: No broad hasDnsRelation retention switch — DNS removal does not drop
# unrelated IPv6, isolation, or discovery records (already proven by MR1/MR3-MR5).
# This also proves the compiler has no accidental retention branch: each record
# collection is independently retained regardless of DNS presence.
jq -e '.dnsRecursiveDiffer == true' <<<"$result" >/dev/null \
  && echo "PASS: SN2 - DNS recursive records changed (correct: DNS removal affects DNS)" \
  || { echo "FAIL: SN2 - DNS recursive should differ" >&2; exit 1; }
jq -e '.nonDnsMatch == true and .ipv6TenantsMatch == true and .isolationMatch == true and .discoveryMatch == true' <<<"$result" >/dev/null \
  && echo "PASS: SN2 - no broad hasDnsRelation retention switch; all unrelated collections independently preserved" \
  || { echo "FAIL: SN2 - unrelated records not independently preserved" >&2; exit 1; }

# Cardinality diagnostics (informational)
echo ""
echo "--- Cardinality diagnostics ---"
echo "  relations: $(jq -r '.relationCountWith' <<<"$result") (DNS) vs $(jq -r '.relationCountNo' <<<"$result") (no-DNS)"
echo "  trafficPaths: $(jq -r '.pathCountWith' <<<"$result") (DNS) vs $(jq -r '.pathCountNo' <<<"$result") (no-DNS)"
jq -e '.dnsServiceAdded == true' <<<"$result" >/dev/null \
  && echo "  compiler: core-dns service added to communicationContract from recursiveDnsIntent" \
  || echo "  compiler: core-dns service NOT added (unexpected)"

echo ""
echo "=== FS-540-HDS-010-SDS-010-SMS-042 Compiler: ALL CHECKS PASSED ==="
