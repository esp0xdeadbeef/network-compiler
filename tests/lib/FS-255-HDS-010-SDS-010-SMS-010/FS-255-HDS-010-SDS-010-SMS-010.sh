#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-255-HDS-010-SDS-010-SMS-010
# GAMP-SCOPE: software-module-test
#
# FS-255/FS-260 at the COMPILER layer: a core exists to make something
# reachable, so the intent must give it two legs -- the fabric ingress to its
# selector and one reachability leg. That leg is either a modeled uplink or, for
# a core whose exit is a selected remote tenant context, the `underlayAccess`
# carriage attachment that carries the tunnel. The remote-egress exemption
# removes the local exit, never the carriage surface.

ROOT="${NETWORK_COMPILER_ROOT:-${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

compile_ok() {
  local input="$1"
  local output="$2"
  nix run "${ROOT}#compile" -- "${input}" >"${output}"
  jq -e '.sites | length > 0' "${output}" >/dev/null
}

expect_compile_failure() {
  local name="$1"
  local input="$2"
  local expected="$3"
  local output
  local rc

  set +e
  output="$(nix run "${ROOT}#compile" -- "${input}" 2>&1)"
  rc=$?
  set -e

  if [[ "${rc}" -eq 0 ]]; then
    echo "FAIL ${name}: expected the compiler to reject a one-leg core" >&2
    exit 1
  fi
  if ! grep -q "${expected}" <<<"${output}"; then
    echo "FAIL ${name}: missing ${expected}" >&2
    printf '%s\n' "${output}" >&2
    exit 1
  fi
  echo "PASS ${name}: rejected with ${expected}"
}

# ---------------------------------------------------------------- case 1 ----
# A core that is not an overlay endpoint and has no uplink: one leg only.
single_leg="${tmp_dir}/single-leg-core.nix"
cat >"${single_leg}" <<'NIX'
{
  esp0xdeadbeef = {
    "site-a" = {
      pools = {
        p2p.ipv4 = "10.10.0.0/24";
        loopback.ipv4 = "10.19.0.0/24";
      };
      ownership.prefixes = [
        { kind = "tenant"; name = "client"; ipv4 = "10.20.20.0/24"; }
      ];
      communicationContract.relations = [
        {
          id = "allow-client-to-wan";
          priority = 100;
          from = { kind = "tenant"; name = "client"; };
          to = { kind = "external"; };
          trafficType = "any";
          action = "allow";
        }
      ];
      topology.nodes = {
        access-client = {
          role = "access";
          attachments = [ { kind = "tenant"; name = "client"; } ];
        };
        downstream.role = "downstream-selector";
        policy.role = "policy";
        upstream.role = "upstream-selector";
        core-single.role = "core";
      };
      topology.links = [
        [ "access-client" "downstream" ]
        [ "downstream" "policy" ]
        [ "policy" "upstream" ]
        [ "upstream" "core-single" ]
      ];
    };
  };
}
NIX

expect_compile_failure "single-leg-core" "${single_leg}" "E_CORE_UPLINKS_REQUIRED"

# ---------------------------------------------------------------- case 2 ----
# An overlay endpoint whose underlayAccess names a tenant the core does not
# attach: still one leg.
overlay_no_carriage="${tmp_dir}/overlay-no-carriage.nix"
cat >"${overlay_no_carriage}" <<'NIX'
{
  esp0xdeadbeef = {
    "site-a" = {
      pools = {
        p2p.ipv4 = "10.10.0.0/24";
        loopback.ipv4 = "10.19.0.0/24";
      };
      ownership.prefixes = [
        { kind = "tenant"; name = "client"; ipv4 = "10.20.20.0/24"; }
        { kind = "tenant"; name = "underlay"; ipv4 = "10.20.51.0/24"; }
      ];
      communicationContract.trafficTypes = [
        { name = "nebula"; match = [ { proto = "udp"; dports = [ 4242 ]; family = "any"; } ]; }
      ];
      communicationContract.relations = [
        {
          id = "allow-client-to-wan";
          priority = 100;
          from = { kind = "tenant"; name = "client"; };
          to = { kind = "external"; };
          trafficType = "any";
          action = "allow";
        }
        {
          id = "allow-underlay-to-nebula";
          priority = 101;
          from = { kind = "tenant"; name = "underlay"; };
          to = { kind = "external"; name = "nebula"; };
          trafficType = "nebula";
          action = "allow";
        }
        {
          id = "allow-underlay-nebula-to-wan";
          priority = 103;
          from = { kind = "tenant"; name = "underlay"; };
          to = { kind = "external"; scope = "core-wan"; };
          trafficType = "nebula";
          action = "allow";
        }
        {
          id = "allow-nebula-underlay";
          priority = 102;
          from = { kind = "external"; name = "nebula"; };
          to = { kind = "external"; scope = "core-wan"; };
          trafficType = "nebula";
          action = "allow";
        }
      ];
      transport.overlays = [
        {
          name = "nebula";
          terminateOn = "core-nebula";
          underlayAccess = { kind = "tenant"; name = "underlay"; };
          underlayTrafficTypes = [ "nebula" ];
          mustTraverse = [ "policy" ];
        }
      ];
      topology.nodes = {
        access-client = {
          role = "access";
          attachments = [ { kind = "tenant"; name = "client"; } ];
        };
        access-underlay = {
          role = "access";
          selects = [ "core-wan" ];
          attachments = [ { kind = "tenant"; name = "underlay"; } ];
        };
        downstream.role = "downstream-selector";
        policy.role = "policy";
        upstream.role = "upstream-selector";
        core-wan = { role = "core"; uplinks.wan.ipv4 = [ "0.0.0.0/0" ]; };
        core-nebula.role = "core";
      };
      topology.links = [
        [ "core-wan" "upstream" ]
        [ "core-nebula" "upstream" ]
        [ "upstream" "policy" ]
        [ "policy" "downstream" ]
        [ "downstream" "access-client" ]
        [ "downstream" "access-underlay" ]
      ];
    };
  };
}
NIX

expect_compile_failure "overlay-endpoint-without-carriage" "${overlay_no_carriage}" "E_CORE_CARRIAGE_REQUIRED"

# ---------------------------------------------------------------- case 3 ----
# The same endpoint with the carriage attachment: two legs, compiles.
overlay_carriage="${tmp_dir}/overlay-with-carriage.nix"
sed 's|core-nebula.role = "core";|core-nebula = { role = "core"; attachments = [ { kind = "tenant"; name = "underlay"; } ]; };|' \
  "${overlay_no_carriage}" >"${overlay_carriage}"
compile_ok "${overlay_carriage}" "${tmp_dir}/overlay-with-carriage.json"
echo "PASS overlay-endpoint-with-carriage: compiles with two legs"

# ---------------------------------------------------------------- case 4 ----
# An endpoint that owns a local exit needs no carriage attachment.
overlay_uplink="${tmp_dir}/overlay-with-uplink.nix"
sed 's|core-nebula.role = "core";|core-nebula = { role = "core"; uplinks.nebula-egress.ipv4 = [ "0.0.0.0/0" ]; };|' \
  "${overlay_no_carriage}" >"${overlay_uplink}"
compile_ok "${overlay_uplink}" "${tmp_dir}/overlay-with-uplink.json"
echo "PASS overlay-endpoint-with-uplink: compiles with a modeled local exit"

echo "PASS FS-255-HDS-010-SDS-010-SMS-010 core reachability legs (compiler)"
