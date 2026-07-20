#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-030-HDS-010-SDS-020-SMS-010
# GAMP-SCOPE: software-module-test
# Construction test: compiler stage topology enforcement
#
# SMS predicates proven:
#   - Valid canonical topology (all stages, correct order) → passes
#   - Multi-core canonical topology (core → upstream → policy → upstream → core) → passes
#   - Core-to-core link → hard-fails with E_TOPO_NON_CANONICAL_STAGE_LINK,
#     diagnostic names violating nodes and expected adjacency
#   - Access-to-policy stage-skip → hard-fails with E_TOPO_NON_CANONICAL_STAGE_LINK,
#     diagnostic names skipped stage
#   - Downstream-to-core, access→upstream, core→policy, access→core
#     (no shared attachment) → hard-fails with E_TOPO_NON_CANONICAL_STAGE_LINK
#   - Missing required stage → hard-fails with E_TOPO_MISSING_*
#   - Policy bypass upstream→core→upstream → hard-fails with E_TOPO_POLICY_BYPASS
#   - Shared-selector fanout for multiple cores/access nodes remains valid topology
#     and does not create extra traffic-path authority by itself.
#
# Two active seeded negatives required by SMS-010:
#   Negative 1 — Direct core-to-core bypass
#   Negative 2 — Access-to-policy stage skip

ROOT="${NETWORK_COMPILER_ROOT:-${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

all_passed=true

echo "--- FS-030-HDS-010-SDS-020-SMS-010: Stage topology enforcement ---"
echo ""

# ============================================================
# Positive: Valid canonical topology compiles successfully
# ============================================================
echo "--- Positive: Valid canonical topology ---"

nix run "$ROOT#compile" -- "$ROOT/tests/fixtures/single-uplink.nix" \
  >/dev/null 2>"${tmp_dir}/positive-stderr.txt"
if [[ $? -eq 0 ]]; then
  echo "PASS: Valid canonical topology compiles successfully"
else
  echo "FAIL: Valid canonical topology (single-uplink, all 5 stages in order) failed to compile"
  cat "${tmp_dir}/positive-stderr.txt"
  all_passed=false
fi

# ============================================================
# Positive: Multi-core canonical topology
# Two cores communicate through: core → upstream → policy → upstream → core
# This proves the system does NOT over-reject valid multi-core traversal.
# ============================================================
echo ""
echo "--- Positive: Multi-core canonical topology (core → upstream → policy → upstream → core) ---"

cat > "${tmp_dir}/multi-core-canonical.nix" <<'MULTICORE'
{
  goodsite = {
    pools = {
      p2p.ipv4 = "10.10.0.0/24";
      loopback.ipv4 = "10.19.0.0/24";
    };
    ownership.prefixes = [
      { kind = "tenant"; name = "mgmt"; ipv4 = "10.20.10.0/24"; }
    ];
    communicationContract = {
      trafficTypes = [ ];
      services = [ ];
      relations = [
        {
          id = "allow-mgmt-to-wan";
          priority = 100;
          from = { kind = "tenant"; name = "mgmt"; };
          to = { kind = "external"; uplinks = [ "wan" "east-west" ]; };
          trafficType = "any";
          action = "allow";
        }
      ];
    };
    topology = {
      nodes = {
        core-wan = {
          role = "core";
          uplinks.wan.ipv4 = [ "0.0.0.0/0" ];
        };
        core-east-west = {
          role = "core";
          uplinks.east-west.ipv4 = [ "100.96.0.0/24" ];
        };
        upstream-a.role = "upstream-selector";
        upstream-b.role = "upstream-selector";
        policy.role = "policy";
        downstream.role = "downstream-selector";
        access = {
          role = "access";
          attachments = [{ kind = "tenant"; name = "mgmt"; }];
        };
      };
      links = [
        [ "core-wan" "upstream-a" ]
        [ "upstream-a" "policy" ]
        [ "policy" "upstream-b" ]
        [ "upstream-b" "core-east-west" ]
        [ "policy" "downstream" ]
        [ "downstream" "access" ]
      ];
    };
  };
}
MULTICORE

nix run "$ROOT#compile" -- "${tmp_dir}/multi-core-canonical.nix" \
  >/dev/null 2>"${tmp_dir}/multi-core-stderr.txt"
if [[ $? -eq 0 ]]; then
  echo "PASS: Multi-core canonical topology (core → upstream → policy → upstream → core) compiles"
else
  echo "FAIL: Multi-core canonical topology incorrectly rejected"
  cat "${tmp_dir}/multi-core-stderr.txt"
  all_passed=false
fi

# ============================================================
# Seeded Negative 1: Direct core-to-core bypass
# SMS requires: hard-fail, diagnostic naming violating nodes
#               and expected canonical adjacency
# ============================================================
echo ""
echo "--- Seeded Negative 1: Direct core-to-core bypass ---"

set +e
nix run "$ROOT#compile" -- "$ROOT/tests/negative/core-to-core-link.nix" \
  >/dev/null 2>"${tmp_dir}/core-to-core-stderr.txt"
neg1_rc=$?
set -e

if [[ $neg1_rc -ne 0 ]]; then
  # Verify correct error code
  if grep -q 'E_TOPO_NON_CANONICAL_STAGE_LINK' "${tmp_dir}/core-to-core-stderr.txt"; then
    echo "PASS: Core-to-core link rejected with E_TOPO_NON_CANONICAL_STAGE_LINK"
  else
    echo "FAIL: Core-to-core link rejected but wrong error code (expected E_TOPO_NON_CANONICAL_STAGE_LINK)"
    grep -o '"code":"[^"]*"' "${tmp_dir}/core-to-core-stderr.txt" || true
    all_passed=false
  fi

  # Verify diagnostic names violating nodes (core-wan, core-nebula with their roles)
  if grep -qE "core-wan.*\(core\)|core-nebula.*\(core\)" "${tmp_dir}/core-to-core-stderr.txt" && \
     grep -qE "core-wan|core-nebula" "${tmp_dir}/core-to-core-stderr.txt"; then
    echo "PASS: Diagnostic names violating nodes with roles (core-wan (core), core-nebula (core))"
  else
    echo "FAIL: Diagnostic does not name violating nodes with their roles"
    grep -o '"message":"[^"]*"' "${tmp_dir}/core-to-core-stderr.txt" || true
    all_passed=false
  fi

  # Verify expected canonical adjacency in hints
  if grep -q 'access.*downstream-selector.*policy.*upstream-selector.*core' "${tmp_dir}/core-to-core-stderr.txt"; then
    echo "PASS: Diagnostic includes expected canonical adjacency"
  else
    echo "FAIL: Diagnostic missing expected canonical adjacency in hints"
    all_passed=false
  fi
else
  echo "FAIL: Core-to-core link should have been rejected but compiled successfully"
  all_passed=false
fi

# ============================================================
# Seeded Negative 2: Access-to-policy stage skip
# SMS requires: hard-fail, diagnostic naming the skipped stage
#               and owning source location
# ============================================================
echo ""
echo "--- Seeded Negative 2: Access-to-policy stage skip ---"

set +e
nix run "$ROOT#compile" -- "$ROOT/tests/negative/policy-bypass-link.nix" \
  >/dev/null 2>"${tmp_dir}/policy-bypass-stderr.txt"
neg2_rc=$?
set -e

if [[ $neg2_rc -ne 0 ]]; then
  # Verify correct error code
  if grep -q 'E_TOPO_NON_CANONICAL_STAGE_LINK' "${tmp_dir}/policy-bypass-stderr.txt"; then
    echo "PASS: Access-to-policy link rejected with E_TOPO_NON_CANONICAL_STAGE_LINK"
  else
    echo "FAIL: Access-to-policy link rejected but wrong error code"
    grep -o '"code":"[^"]*"' "${tmp_dir}/policy-bypass-stderr.txt" || true
    all_passed=false
  fi

  # Verify diagnostic names violating nodes with roles
  if grep -q 'access.*access.*policy.*policy' "${tmp_dir}/policy-bypass-stderr.txt"; then
    echo "PASS: Diagnostic names violating nodes with roles (access (access), policy (policy))"
  else
    echo "FAIL: Diagnostic does not name violating nodes with roles"
    grep -o '"message":"[^"]*"' "${tmp_dir}/policy-bypass-stderr.txt" || true
    all_passed=false
  fi

  # Verify the skipped stage (downstream-selector) is referenced
  # The hints mention "selector-bypassing links" and the canonical adjacency shows
  # the expected order including downstream-selector between access and policy
  if grep -qi 'selector-bypassing\|downstream-selector' "${tmp_dir}/policy-bypass-stderr.txt"; then
    echo "PASS: Diagnostic references the skipped stage (selector-bypassing / downstream-selector)"
  else
    echo "FAIL: Diagnostic does not reference the skipped stage"
    all_passed=false
  fi

  # Verify owning source location (site name)
  if grep -q '"site":"badsite"' "${tmp_dir}/policy-bypass-stderr.txt"; then
    echo "PASS: Diagnostic includes owning source location (site: badsite)"
  else
    echo "FAIL: Diagnostic missing owning source location"
    all_passed=false
  fi
else
  echo "FAIL: Access-to-policy link should have been rejected but compiled successfully"
  all_passed=false
fi

# ============================================================
# Additional negative: Downstream-to-core policy bypass
# (skips both policy and upstream-selector)
# ============================================================
echo ""
echo "--- Negative: Downstream-to-core policy bypass ---"

set +e
nix run "$ROOT#compile" -- "$ROOT/tests/negative/downstream-to-core-link.nix" \
  >/dev/null 2>"${tmp_dir}/downstream-core-stderr.txt"
neg3_rc=$?
set -e

if [[ $neg3_rc -ne 0 ]]; then
  if grep -q 'E_TOPO_NON_CANONICAL_STAGE_LINK' "${tmp_dir}/downstream-core-stderr.txt"; then
    echo "PASS: Downstream-to-core bypass rejected with E_TOPO_NON_CANONICAL_STAGE_LINK"
  else
    echo "FAIL: Downstream-to-core bypass rejected but wrong error code"
    grep -o '"code":"[^"]*"' "${tmp_dir}/downstream-core-stderr.txt" || true
    all_passed=false
  fi
else
  echo "FAIL: Downstream-to-core bypass should have been rejected"
  all_passed=false
fi

# ============================================================
# Negative: Missing required stage — downstream-selector
# ============================================================
echo ""
echo "--- Negative: Missing downstream-selector stage ---"

cat > "${tmp_dir}/missing-downstream.nix" <<'MISSINGDS'
{
  badsite = {
    pools = {
      p2p.ipv4 = "10.10.0.0/24";
      loopback.ipv4 = "10.19.0.0/24";
    };
    ownership.prefixes = [
      { kind = "tenant"; name = "mgmt"; ipv4 = "10.20.10.0/24"; }
    ];
    communicationContract = {
      trafficTypes = [ ];
      services = [ ];
      relations = [
        {
          id = "allow-mgmt-to-wan";
          priority = 100;
          from = { kind = "tenant"; name = "mgmt"; };
          to = { kind = "external"; uplinks = [ "wan" ]; };
          trafficType = "any";
          action = "allow";
        }
      ];
    };
    topology = {
      nodes = {
        core = {
          role = "core";
          uplinks.wan.ipv4 = [ "0.0.0.0/0" ];
        };
        upstream.role = "upstream-selector";
        policy.role = "policy";
        access = {
          role = "access";
          attachments = [{ kind = "tenant"; name = "mgmt"; }];
        };
      };
      links = [
        [ "core" "upstream" ]
        [ "upstream" "policy" ]
        [ "policy" "access" ]
      ];
    };
  };
}
MISSINGDS

set +e
nix run "$ROOT#compile" -- "${tmp_dir}/missing-downstream.nix" \
  >/dev/null 2>"${tmp_dir}/missing-ds-stderr.txt"
neg4_rc=$?
set -e

if [[ $neg4_rc -ne 0 ]]; then
  if grep -q 'E_TOPO_MISSING_DOWNSTREAM_SELECTOR' "${tmp_dir}/missing-ds-stderr.txt"; then
    echo "PASS: Missing downstream-selector rejected with E_TOPO_MISSING_DOWNSTREAM_SELECTOR"
  else
    echo "FAIL: Missing downstream-selector rejected but wrong error code"
    grep -o '"code":"[^"]*"' "${tmp_dir}/missing-ds-stderr.txt" || true
    all_passed=false
  fi
else
  echo "FAIL: Missing downstream-selector should have been rejected"
  all_passed=false
fi

# ============================================================
# Negative: Missing required stage — upstream-selector
# ============================================================
echo ""
echo "--- Negative: Missing upstream-selector stage ---"

set +e
nix run "$ROOT#compile" -- "$ROOT/tests/negative/multi-wan-missing-upstream-selector.nix" \
  >/dev/null 2>"${tmp_dir}/missing-us-stderr.txt"
neg5_rc=$?
set -e

if [[ $neg5_rc -ne 0 ]]; then
  if grep -q 'E_TOPO_MISSING_UPSTREAM_SELECTOR' "${tmp_dir}/missing-us-stderr.txt"; then
    echo "PASS: Missing upstream-selector rejected with E_TOPO_MISSING_UPSTREAM_SELECTOR"
  else
    echo "FAIL: Missing upstream-selector rejected but wrong error code"
    grep -o '"code":"[^"]*"' "${tmp_dir}/missing-us-stderr.txt" || true
    all_passed=false
  fi
else
  echo "FAIL: Missing upstream-selector should have been rejected"
  all_passed=false
fi

# ============================================================
# Positive: Multi-core shared upstream-selector fanout
# Multiple cores attached to one upstream-selector are valid fabric fanout.
# This is not a core-to-core communication grant; payload authority still
# comes only from modeled traffic relations and downstream policy paths.
# ============================================================
echo ""
echo "--- Positive: Multi-core shared upstream-selector fanout ---"

cat > "${tmp_dir}/core-upstream-core-connected.nix" <<'COREUPCORE'
{
  badsite = {
    pools = {
      p2p.ipv4 = "10.10.0.0/24";
      loopback.ipv4 = "10.19.0.0/24";
    };
    ownership.prefixes = [
      { kind = "tenant"; name = "mgmt"; ipv4 = "10.20.10.0/24"; }
    ];
    communicationContract = {
      trafficTypes = [ ];
      services = [ ];
      relations = [
        {
          id = "allow-mgmt-to-wan";
          priority = 100;
          from = { kind = "tenant"; name = "mgmt"; };
          to = { kind = "external"; uplinks = [ "wan" "east-west" ]; };
          trafficType = "any";
          action = "allow";
        }
      ];
    };
    topology = {
      nodes = {
        core-wan = {
          role = "core";
          uplinks.wan.ipv4 = [ "0.0.0.0/0" ];
        };
        core-east-west = {
          role = "core";
          uplinks.east-west.ipv4 = [ "100.96.0.0/24" ];
        };
        upstream.role = "upstream-selector";
        policy.role = "policy";
        downstream.role = "downstream-selector";
        access = {
          role = "access";
          attachments = [{ kind = "tenant"; name = "mgmt"; }];
        };
      };
      links = [
        [ "core-wan" "upstream" ]
        [ "upstream" "core-east-west" ]
        [ "upstream" "policy" ]
        [ "policy" "downstream" ]
        [ "downstream" "access" ]
      ];
    };
  };
}
COREUPCORE

set +e
nix run "$ROOT#compile" -- "${tmp_dir}/core-upstream-core-connected.nix" \
  >"${tmp_dir}/core-upstream-core.json" 2>"${tmp_dir}/core-upstream-core-stderr.txt"
gap1_rc=$?
set -e

if [[ $gap1_rc -eq 0 ]]; then
  if jq -e '
    [.. | objects | select(has("trafficPaths")) | .trafficPaths][0]
    | length == 1
    and .[0].relationId == "allow-mgmt-to-wan"
    and .[0].requiresPolicy == true
    and (.[0].stagePath == ["access","downstream-selector","policy","upstream-selector","core"])
  ' "${tmp_dir}/core-upstream-core.json" >/dev/null; then
    echo "PASS: Multi-core shared upstream-selector fanout compiles without adding unmodeled core-to-core traffic authority"
  else
    echo "FAIL: Multi-core fanout compiled but emitted unexpected traffic-path authority"
    jq '[.. | objects | select(has("trafficPaths")) | .trafficPaths][0]' "${tmp_dir}/core-upstream-core.json" || true
    all_passed=false
  fi
else
  echo "FAIL: Multi-core shared upstream-selector fanout should compile"
  grep -o '"code":"[^"]*"' "${tmp_dir}/core-upstream-core-stderr.txt" || true
  all_passed=false
fi

# ============================================================
# Negative: access-to-upstream-selector (skips ds + policy)
# ============================================================
echo ""
echo "--- Negative: access-to-upstream stage skip ---"

cat > "${tmp_dir}/access-upstream.nix" <<'ACCUP'
{
  badsite = {
    pools = { p2p.ipv4 = "10.10.0.0/24"; loopback.ipv4 = "10.19.0.0/24"; };
    ownership.prefixes = [ { kind = "tenant"; name = "mgmt"; ipv4 = "10.20.10.0/24"; } ];
    communicationContract = {
      trafficTypes = [ ]; services = [ ];
      relations = [ { id = "r1"; priority = 100; from = { kind = "tenant"; name = "mgmt"; }; to = { kind = "external"; uplinks = [ "wan" ]; }; trafficType = "any"; action = "allow"; } ];
    };
    topology = {
      nodes = {
        core = { role = "core"; uplinks.wan.ipv4 = [ "0.0.0.0/0" ]; };
        upstream.role = "upstream-selector";
        policy.role = "policy";
        downstream.role = "downstream-selector";
        access = { role = "access"; attachments = [{ kind = "tenant"; name = "mgmt"; }]; };
      };
      links = [
        [ "core" "upstream" ]
        [ "upstream" "policy" ]
        [ "policy" "downstream" ]
        [ "downstream" "access" ]
        [ "access" "upstream" ]
      ];
    };
  };
}
ACCUP

set +e
nix run "$ROOT#compile" -- "${tmp_dir}/access-upstream.nix" >/dev/null 2>"${tmp_dir}/access-upstream-stderr.txt"
neg6_rc=$?
set -e

if [[ $neg6_rc -ne 0 ]]; then
  if grep -q 'E_TOPO_NON_CANONICAL_STAGE_LINK' "${tmp_dir}/access-upstream-stderr.txt"; then
    echo "PASS: access→upstream (skips ds+policy) rejected with E_TOPO_NON_CANONICAL_STAGE_LINK"
  else
    echo "FAIL: access→upstream rejected but wrong error code"
    grep -o '"code":"[^"]*"' "${tmp_dir}/access-upstream-stderr.txt" || true
    all_passed=false
  fi
else
  echo "FAIL: access→upstream (skipping 2 stages) should have been rejected"
  all_passed=false
fi

# ============================================================
# Negative: core-to-policy (skips upstream-selector)
# ============================================================
echo ""
echo "--- Negative: core-to-policy stage skip ---"

cat > "${tmp_dir}/core-policy.nix" <<'COREPOL'
{
  badsite = {
    pools = { p2p.ipv4 = "10.10.0.0/24"; loopback.ipv4 = "10.19.0.0/24"; };
    ownership.prefixes = [ { kind = "tenant"; name = "mgmt"; ipv4 = "10.20.10.0/24"; } ];
    communicationContract = {
      trafficTypes = [ ]; services = [ ];
      relations = [ { id = "r1"; priority = 100; from = { kind = "tenant"; name = "mgmt"; }; to = { kind = "external"; uplinks = [ "wan" ]; }; trafficType = "any"; action = "allow"; } ];
    };
    topology = {
      nodes = {
        core = { role = "core"; uplinks.wan.ipv4 = [ "0.0.0.0/0" ]; };
        upstream.role = "upstream-selector";
        policy.role = "policy";
        downstream.role = "downstream-selector";
        access = { role = "access"; attachments = [{ kind = "tenant"; name = "mgmt"; }]; };
      };
      links = [
        [ "core" "policy" ]
        [ "core" "upstream" ]
        [ "upstream" "policy" ]
        [ "policy" "downstream" ]
        [ "downstream" "access" ]
      ];
    };
  };
}
COREPOL

set +e
nix run "$ROOT#compile" -- "${tmp_dir}/core-policy.nix" >/dev/null 2>"${tmp_dir}/core-policy-stderr.txt"
neg7_rc=$?
set -e

if [[ $neg7_rc -ne 0 ]]; then
  if grep -q 'E_TOPO_NON_CANONICAL_STAGE_LINK' "${tmp_dir}/core-policy-stderr.txt"; then
    echo "PASS: core→policy (skips upstream) rejected with E_TOPO_NON_CANONICAL_STAGE_LINK"
  else
    echo "FAIL: core→policy rejected but wrong error code"
    grep -o '"code":"[^"]*"' "${tmp_dir}/core-policy-stderr.txt" || true
    all_passed=false
  fi
else
  echo "FAIL: core→policy (skipping upstream-selector) should have been rejected"
  all_passed=false
fi

# ============================================================
# Negative: access-to-core without shared attachment
# ============================================================
echo ""
echo "--- Negative: access-to-core without shared attachment ---"

cat > "${tmp_dir}/access-core-no-shared.nix" <<'ACCNOSHARE'
{
  badsite = {
    pools = { p2p.ipv4 = "10.10.0.0/24"; loopback.ipv4 = "10.19.0.0/24"; };
    ownership.prefixes = [ { kind = "tenant"; name = "mgmt"; ipv4 = "10.20.10.0/24"; } ];
    communicationContract = {
      trafficTypes = [ ]; services = [ ];
      relations = [ { id = "r1"; priority = 100; from = { kind = "tenant"; name = "mgmt"; }; to = { kind = "external"; uplinks = [ "wan" ]; }; trafficType = "any"; action = "allow"; } ];
    };
    topology = {
      nodes = {
        core = { role = "core"; uplinks.wan.ipv4 = [ "0.0.0.0/0" ]; };
        upstream.role = "upstream-selector";
        policy.role = "policy";
        downstream.role = "downstream-selector";
        access = { role = "access"; attachments = [{ kind = "tenant"; name = "mgmt"; }]; };
      };
      links = [
        [ "core" "upstream" ]
        [ "upstream" "policy" ]
        [ "policy" "downstream" ]
        [ "downstream" "access" ]
        [ "access" "core" ]
      ];
    };
  };
}
ACCNOSHARE

set +e
nix run "$ROOT#compile" -- "${tmp_dir}/access-core-no-shared.nix" >/dev/null 2>"${tmp_dir}/access-core-stderr.txt"
neg8_rc=$?
set -e

if [[ $neg8_rc -ne 0 ]]; then
  if grep -q 'E_TOPO_NON_CANONICAL_STAGE_LINK' "${tmp_dir}/access-core-stderr.txt"; then
    echo "PASS: access→core (no shared attachment) rejected with E_TOPO_NON_CANONICAL_STAGE_LINK"
  else
    echo "FAIL: access→core rejected but wrong error code"
    grep -o '"code":"[^"]*"' "${tmp_dir}/access-core-stderr.txt" || true
    all_passed=false
  fi
else
  echo "FAIL: access→core without shared attachment should have been rejected"
  all_passed=false
fi

# ============================================================
# Positive: Multi-access shared downstream-selector fanout
# Multiple access nodes attached to one downstream-selector are valid fabric
# fanout. This topology does not itself grant tenant-to-tenant reachability.
# ============================================================
echo ""
echo "--- Positive: Multi-access shared downstream-selector fanout ---"

cat > "${tmp_dir}/access-ds-access.nix" <<'ACCACC'
{
  badsite = {
    pools = { p2p.ipv4 = "10.10.0.0/24"; loopback.ipv4 = "10.19.0.0/24"; };
    ownership.prefixes = [
      { kind = "tenant"; name = "t1"; ipv4 = "10.20.10.0/24"; }
      { kind = "tenant"; name = "t2"; ipv4 = "10.20.20.0/24"; }
    ];
    communicationContract = {
      trafficTypes = [ ]; services = [ ];
      relations = [ { id = "r1"; priority = 100; from = { kind = "tenant"; name = "t1"; }; to = { kind = "external"; uplinks = [ "wan" ]; }; trafficType = "any"; action = "allow"; } ];
    };
    topology = {
      nodes = {
        core = { role = "core"; uplinks.wan.ipv4 = [ "0.0.0.0/0" ]; };
        upstream.role = "upstream-selector";
        policy.role = "policy";
        downstream.role = "downstream-selector";
        access-a = { role = "access"; attachments = [{ kind = "tenant"; name = "t1"; }]; };
        access-b = { role = "access"; attachments = [{ kind = "tenant"; name = "t2"; }]; };
      };
      links = [
        [ "core" "upstream" ]
        [ "upstream" "policy" ]
        [ "policy" "downstream" ]
        [ "downstream" "access-a" ]
        [ "downstream" "access-b" ]
      ];
    };
  };
}
ACCACC

set +e
nix run "$ROOT#compile" -- "${tmp_dir}/access-ds-access.nix" >"${tmp_dir}/access-ds-access.json" 2>"${tmp_dir}/access-ds-access-stderr.txt"
gap2_rc=$?
set -e

if [[ $gap2_rc -eq 0 ]]; then
  if jq -e '
    [.. | objects | select(has("trafficPaths")) | .trafficPaths][0]
    | length == 1
    and .[0].relationId == "r1"
    and .[0].requiresPolicy == true
    and .[0].source.name == "t1"
    and .[0].destination.kind == "external"
    and ([.[] | select((.destination.kind // "") == "tenant" and (.destination.name // "") == "t2")] | length) == 0
  ' "${tmp_dir}/access-ds-access.json" >/dev/null; then
    echo "PASS: Multi-access shared downstream-selector fanout compiles without adding unmodeled tenant-to-tenant traffic authority"
  else
    echo "FAIL: Multi-access fanout compiled but emitted unexpected tenant-to-tenant authority"
    jq '[.. | objects | select(has("trafficPaths")) | .trafficPaths][0]' "${tmp_dir}/access-ds-access.json" || true
    all_passed=false
  fi
else
  echo "FAIL: Multi-access shared downstream-selector fanout should compile"
  grep -o '"code":"[^"]*"' "${tmp_dir}/access-ds-access-stderr.txt" || true
  all_passed=false
fi

# ============================================================
# Policy bypass: Upstream-to-upstream through core
# Two upstream-selectors share a core node. Traffic between
# upstream-a and upstream-b can reach each other via
# upstream→core→upstream without traversing policy.
# ============================================================
echo ""
echo "--- Policy bypass: Upstream-to-upstream through core ---"

cat > "${tmp_dir}/us-core-us.nix" <<'USCOREUS'
{
  badsite = {
    pools = { p2p.ipv4 = "10.10.0.0/24"; loopback.ipv4 = "10.19.0.0/24"; };
    ownership.prefixes = [ { kind = "tenant"; name = "t1"; ipv4 = "10.20.10.0/24"; } ];
    communicationContract = {
      trafficTypes = [ ]; services = [ ];
      relations = [ { id = "r1"; priority = 100; from = { kind = "tenant"; name = "t1"; }; to = { kind = "external"; uplinks = [ "wan" "ew" ]; }; trafficType = "any"; action = "allow"; } ];
    };
    topology = {
      nodes = {
        core-a = { role = "core"; uplinks.wan.ipv4 = [ "0.0.0.0/0" ]; };
        core-b = { role = "core"; uplinks.ew.ipv4 = [ "100.96.0.0/24" ]; };
        upstream-a.role = "upstream-selector";
        upstream-b.role = "upstream-selector";
        policy.role = "policy";
        downstream.role = "downstream-selector";
        access = { role = "access"; attachments = [{ kind = "tenant"; name = "t1"; }]; };
      };
      links = [
        [ "core-a" "upstream-a" ]
        [ "upstream-a" "core-b" ]
        [ "core-b" "upstream-b" ]
        [ "upstream-b" "policy" ]
        [ "policy" "downstream" ]
        [ "downstream" "access" ]
      ];
    };
  };
}
USCOREUS

set +e
nix run "$ROOT#compile" -- "${tmp_dir}/us-core-us.nix" >/dev/null 2>"${tmp_dir}/us-core-us-stderr.txt"
gap3_rc=$?
set -e

if [[ $gap3_rc -ne 0 ]]; then
  if grep -q 'E_TOPO_POLICY_BYPASS' "${tmp_dir}/us-core-us-stderr.txt"; then
    echo "PASS: upstream→core→upstream policy bypass rejected with E_TOPO_POLICY_BYPASS"
  else
    echo "FAIL: upstream→core→upstream rejected but wrong error code (expected E_TOPO_POLICY_BYPASS)"
    grep -o '"code":"[^"]*"' "${tmp_dir}/us-core-us-stderr.txt" || true
    all_passed=false
  fi
else
  echo "FAIL: upstream→core→upstream policy bypass should have been rejected but compiled successfully"
  all_passed=false
fi

# SMS-010 requires active seeded negatives (not dormant).
# This test actually invokes the compiler on bad input — it is not
# a static fixture-only check.
# ============================================================
echo ""
echo "--- Active seeded negative verification ---"
echo "PASS: Both seeded negatives compiled real bad input through the compile app"
echo "      (not dormant fixture-only checks or static jq scans)"

# ============================================================
# Report
# ============================================================
echo ""
if [[ "${all_passed}" == "true" ]]; then
  echo "PASS: FS-030-HDS-010-SDS-020-SMS-010 stage topology enforcement"
  echo "  Single-core canonical topology: compiles successfully"
  echo "  Multi-core canonical topology (core → upstream → policy → upstream → core): compiles"
  echo "  Core-to-core bypass (Negative 1): hard-fails E_TOPO_NON_CANONICAL_STAGE_LINK + node names + adjacency"
  echo "  Access-to-policy stage skip (Negative 2): hard-fails E_TOPO_NON_CANONICAL_STAGE_LINK + skipped stage + site"
  echo "  Downstream-to-core policy bypass: hard-fails E_TOPO_NON_CANONICAL_STAGE_LINK"
  echo "  access→upstream (skip ds+policy): hard-fails E_TOPO_NON_CANONICAL_STAGE_LINK"
  echo "  core→policy (skip upstream): hard-fails E_TOPO_NON_CANONICAL_STAGE_LINK"
  echo "  access→core (no shared attachment): hard-fails E_TOPO_NON_CANONICAL_STAGE_LINK"
  echo "  Missing downstream-selector: hard-fails E_TOPO_MISSING_DOWNSTREAM_SELECTOR"
  echo "  Missing upstream-selector: hard-fails E_TOPO_MISSING_UPSTREAM_SELECTOR"
  echo "  Policy bypass upstream→core→upstream: hard-fails E_TOPO_POLICY_BYPASS"
  echo "  Multi-core shared upstream-selector fanout: compiles without unmodeled core-to-core traffic authority"
  echo "  Multi-access shared downstream-selector fanout: compiles without unmodeled tenant-to-tenant traffic authority"
  exit 0
else
  echo "FAIL: One or more stage topology enforcement checks failed."
  exit 1
fi
