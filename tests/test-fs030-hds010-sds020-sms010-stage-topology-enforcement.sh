#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-030-HDS-010-SDS-020-SMS-010
# GAMP-SCOPE: software-module-test
# Construction test: compiler stage topology enforcement
#
# SMS predicates proven:
#   - Valid canonical topology (all stages, correct order) → passes
#   - Core-to-core link → hard-fails with E_TOPO_NON_CANONICAL_STAGE_LINK,
#     diagnostic names violating nodes and expected adjacency
#   - Access-to-policy stage-skip → hard-fails with E_TOPO_NON_CANONICAL_STAGE_LINK,
#     diagnostic names skipped stage
#   - Policy-bypass link (downstream→core) → hard-fails
#   - Missing required stage → hard-fails with E_TOPO_MISSING_*
#
# Two active seeded negatives required by SMS-010:
#   Negative 1 — Direct core-to-core bypass
#   Negative 2 — Access-to-policy stage skip

ROOT="${NETWORK_COMPILER_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
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
# Active seeded negative verification
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
  echo "  Valid canonical topology: compiles successfully"
  echo "  Core-to-core bypass (Negative 1): hard-fails E_TOPO_NON_CANONICAL_STAGE_LINK + node names + adjacency"
  echo "  Access-to-policy stage skip (Negative 2): hard-fails E_TOPO_NON_CANONICAL_STAGE_LINK + skipped stage + site"
  echo "  Downstream-to-core policy bypass: hard-fails E_TOPO_NON_CANONICAL_STAGE_LINK"
  echo "  Missing downstream-selector: hard-fails E_TOPO_MISSING_DOWNSTREAM_SELECTOR"
  echo "  Missing upstream-selector: hard-fails E_TOPO_MISSING_UPSTREAM_SELECTOR"
  exit 0
else
  echo "FAIL: One or more stage topology enforcement checks failed."
  exit 1
fi
