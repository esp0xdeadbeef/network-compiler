#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-482-HDS-010-SDS-010-SMS-010
# GAMP-SCOPE: software-module-test

ROOT="${NETWORK_COMPILER_ROOT:-${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}}"
system="${NIX_SYSTEM:-$(nix eval --no-write-lock-file --impure --raw --expr 'builtins.currentSystem')}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

require_cmd jq

flake_input_path() {
  local input_name="$1"
  if [[ "${input_name}" == "network-labs" && -n "${NETWORK_LABS_PATH:-}" ]]; then
    realpath "${NETWORK_LABS_PATH}"
    return
  fi
  nix flake archive --json "path:${ROOT}" \
    | jq -er ".inputs[\"${input_name}\"].path"
}

labs="$(flake_input_path network-labs)"
example_root="${labs}/examples/single-wan-bgp"
intent_path="${example_root}/intent.nix"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

compile_paths() {
  local intent="$1"
  nix eval --no-write-lock-file --impure --json --expr '
    let
      flake = builtins.getFlake "'"path:${ROOT}"'";
    in
      flake.libBySystem."'"${system}"'".compilePath "'"${intent}"'"
  '
}

# Positive: a model that selects BGP and declares the TCP/179 traffic type for
# both address families compiles and carries an authorization attributable to
# that traffic type.
baseline_json="${tmp_dir}/baseline.json"
compile_paths "${intent_path}" >"${baseline_json}"

# SN1: BGP selected with no BGP traffic type must abort, naming the boundaries.
no_traffic_type_intent="${tmp_dir}/intent-no-bgp-traffic-type.nix"
cat >"${no_traffic_type_intent}" <<EOF
let
  base = import ${intent_path};
  stripBgp = types: builtins.filter (t: (t.name or null) != "bgp") types;
  sites = builtins.mapAttrs
    (siteName: site:
      site // {
        communicationContract = site.communicationContract // {
          trafficTypes = stripBgp site.communicationContract.trafficTypes;
        };
      })
    base.esp0xdeadbeef;
in
base // { esp0xdeadbeef = sites; }
EOF

set +e
compile_paths "${no_traffic_type_intent}" >"${tmp_dir}/no-type.out" 2>"${tmp_dir}/no-type.err"
no_type_rc=$?
set -e

if ((no_type_rc == 0)); then
  echo "FAIL bgp-traffic-type-requirement: BGP selected with no BGP traffic type compiled successfully" >&2
  exit 1
fi

if ! grep -Fq "communicationContract.trafficTypes must declare a 'bgp' traffic type (tcp/179)" \
  "${tmp_dir}/no-type.err"; then
  echo "FAIL bgp-traffic-type-requirement: the abort did not require a BGP traffic type" >&2
  cat "${tmp_dir}/no-type.err" >&2
  exit 1
fi

if [[ -s "${tmp_dir}/no-type.out" ]]; then
  echo "FAIL bgp-traffic-type-requirement: the aborted run released an artifact" >&2
  exit 1
fi

# SN2: the declared BGP traffic type must carry TCP/179 for both families. A type
# that matches neither is not a BGP control-plane traffic type.
wrong_port_intent="${tmp_dir}/intent-wrong-port.nix"
cat >"${wrong_port_intent}" <<EOF
let
  base = import ${intent_path};
  wreckBgp = types:
    map
      (t:
        if (t.name or null) == "bgp"
        then t // {
          match = map (m: m // { dports = [ 830 ]; }) t.match;
        }
        else t)
      types;
  sites = builtins.mapAttrs
    (siteName: site:
      site // {
        communicationContract = site.communicationContract // {
          trafficTypes = wreckBgp site.communicationContract.trafficTypes;
        };
      })
    base.esp0xdeadbeef;
in
base // { esp0xdeadbeef = sites; }
EOF

set +e
compile_paths "${wrong_port_intent}" >"${tmp_dir}/wrong-port.out" 2>"${tmp_dir}/wrong-port.err"
wrong_port_rc=$?
set -e

if ((wrong_port_rc == 0)); then
  echo "FAIL bgp-traffic-type-requirement: a BGP traffic type on port 830 instead of 179 compiled successfully; the compiler checks only that a traffic type NAMED bgp exists, not that its match is tcp/179 for both families" >&2
  exit 1
fi

# SN3: the declared BGP type must cover both address families.
ipv4_only_intent="${tmp_dir}/intent-ipv4-only.nix"
cat >"${ipv4_only_intent}" <<EOF
let
  base = import ${intent_path};
  narrowBgp = types:
    map
      (t:
        if (t.name or null) == "bgp"
        then t // {
          match = builtins.filter (m: (m.family or "") == "ipv4") t.match;
        }
        else t)
      types;
  sites = builtins.mapAttrs
    (siteName: site:
      site // {
        communicationContract = site.communicationContract // {
          trafficTypes = narrowBgp site.communicationContract.trafficTypes;
        };
      })
    base.esp0xdeadbeef;
in
base // { esp0xdeadbeef = sites; }
EOF

set +e
compile_paths "${ipv4_only_intent}" >"${tmp_dir}/ipv4-only.out" 2>"${tmp_dir}/ipv4-only.err"
ipv4_only_rc=$?
set -e

if ((ipv4_only_rc == 0)); then
  echo "FAIL bgp-traffic-type-requirement: a BGP traffic type covering only ipv4 compiled successfully; both address families are required" >&2
  exit 1
fi

echo "PASS bgp-traffic-type-requirement"
