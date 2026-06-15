#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-180-HDS-010-SDS-010-SMS-030
# GAMP-ID: SMT-COMP-FS180-WILDCARD-LABS-001
# GAMP-SCOPE: software-module-test

ROOT="${NETWORK_COMPILER_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

archive_json="${tmp_dir}/archive.json"
actual_json="${tmp_dir}/actual.json"
expected_json="${tmp_dir}/expected.json"

nix flake archive --json "path:${ROOT}" >"${archive_json}"
labs_path="$(
  ARCHIVE_JSON="${archive_json}" nix eval --impure --raw --expr '
    let
      archived = builtins.fromJSON (builtins.readFile (builtins.getEnv "ARCHIVE_JSON"));
      labsPath = archived.inputs."network-labs".path or null;
    in
      if labsPath == null then throw "network-labs wildcard traffic paths: missing network-labs input" else labsPath
  '
)"

compile_example() {
  local example="$1"
  local output_json="$2"
  nix run "$ROOT#compile" -- "${labs_path}/examples/${example}/intent.nix" >"${output_json}"
}

collect_projection() {
  local example="$1"
  local input_json="$2"
  jq --arg example "${example}" '
    [
      .sites
      | to_entries[]
      | .key as $enterprise
      | .value
      | to_entries[]
      | .key as $site
      | .value.trafficPaths[]?
      | select(.destination == "any")
      | {
          example: $example,
          enterprise: $enterprise,
          site: $site,
          relationId,
          stagePath,
          lastHops: [(.nodePathAlternatives // [])[] | .[-1]]
        }
    ]
  ' "${input_json}"
}

compile_example "ipv6-pd-downstream-delegation" "${tmp_dir}/ipv6.json"
compile_example "single-wan-with-nebula-any-to-any-fw" "${tmp_dir}/single-wan.json"
compile_example "tri-site-s-router-overlay-egress" "${tmp_dir}/tri-site.json"

assert_wildcard_paths_match_modeled_relations() {
  local example="$1"
  local input_json="$2"

  jq -e --arg example "${example}" '
    [
      .sites
      | to_entries[]
      | .key as $enterprise
      | .value
      | to_entries[]
      | .key as $site
      | .value as $siteValue
      | {
          enterprise: $enterprise,
          site: $site,
          modeled: ([
            $siteValue.relations[]?
            | select(.to == "any")
            | .source.id
          ] | sort),
          emitted: ([
            $siteValue.trafficPaths[]?
            | select(.destination == "any")
            | .relationId
          ] | sort)
        }
    ] as $rows
    | all($rows[]; .modeled == .emitted)
      and any($rows[]; (.emitted | length) > 0)
  ' "${input_json}" >/dev/null || {
    echo "FAIL ${example}: wildcard traffic paths do not match modeled to = \"any\" relations" >&2
    jq '
      .sites
      | to_entries[]
      | .key as $enterprise
      | .value
      | to_entries[]
      | .key as $site
      | .value as $siteValue
      | {
          enterprise: $enterprise,
          site: $site,
          modeled: ([$siteValue.relations[]? | select(.to == "any") | .source.id] | sort),
          emitted: ([$siteValue.trafficPaths[]? | select(.destination == "any") | .relationId] | sort)
        }
    ' "${input_json}" >&2
    exit 1
  }
}

assert_wildcard_paths_match_modeled_relations "ipv6-pd-downstream-delegation" "${tmp_dir}/ipv6.json"
assert_wildcard_paths_match_modeled_relations "single-wan-with-nebula-any-to-any-fw" "${tmp_dir}/single-wan.json"
assert_wildcard_paths_match_modeled_relations "tri-site-s-router-overlay-egress" "${tmp_dir}/tri-site.json"

jq -s '
  add
  | sort_by(.example, .enterprise, .site, .relationId)
' \
  <(collect_projection "ipv6-pd-downstream-delegation" "${tmp_dir}/ipv6.json") \
  <(collect_projection "single-wan-with-nebula-any-to-any-fw" "${tmp_dir}/single-wan.json") \
  <(collect_projection "tri-site-s-router-overlay-egress" "${tmp_dir}/tri-site.json") \
  >"${actual_json}"

cat >"${expected_json}" <<'JSON'
[
  {
    "example": "ipv6-pd-downstream-delegation",
    "enterprise": "esp0xdeadbeef",
    "site": "site-a",
    "relationId": "allow-icmp-anywhere",
    "stagePath": [
      "access",
      "downstream-selector",
      "policy",
      "downstream-selector",
      "access"
    ],
    "lastHops": [
      "s-router-access-admin",
      "s-router-access-client-a",
      "s-router-access-client-b",
      "s-router-access-mgmt"
    ]
  },
  {
    "example": "single-wan-with-nebula-any-to-any-fw",
    "enterprise": "esp0xdeadbeef",
    "site": "site-a",
    "relationId": "allow-admin-to-any",
    "stagePath": [
      "access",
      "downstream-selector",
      "policy",
      "downstream-selector",
      "access"
    ],
    "lastHops": [
      "s-router-access-admin",
      "s-router-access-client",
      "s-router-access-mgmt"
    ]
  },
  {
    "example": "single-wan-with-nebula-any-to-any-fw",
    "enterprise": "esp0xdeadbeef",
    "site": "site-a",
    "relationId": "allow-client-to-any",
    "stagePath": [
      "access",
      "downstream-selector",
      "policy",
      "downstream-selector",
      "access"
    ],
    "lastHops": [
      "s-router-access-admin",
      "s-router-access-client",
      "s-router-access-mgmt"
    ]
  },
  {
    "example": "single-wan-with-nebula-any-to-any-fw",
    "enterprise": "esp0xdeadbeef",
    "site": "site-a",
    "relationId": "allow-mgmt-to-any",
    "stagePath": [
      "access",
      "downstream-selector",
      "policy",
      "downstream-selector",
      "access"
    ],
    "lastHops": [
      "s-router-access-admin",
      "s-router-access-client",
      "s-router-access-mgmt"
    ]
  },
  {
    "example": "tri-site-s-router-overlay-egress",
    "enterprise": "esp",
    "site": "edge",
    "relationId": "allow-edge-overlay-icmp-anywhere",
    "stagePath": [
      "core",
      "access",
      "downstream-selector",
      "policy",
      "downstream-selector",
      "access"
    ],
    "lastHops": [
      "edge-example-router-access-client",
      "edge-example-router-access-dmz"
    ]
  },
  {
    "example": "tri-site-s-router-overlay-egress",
    "enterprise": "esp",
    "site": "edge",
    "relationId": "allow-edge-wan-icmp-anywhere",
    "stagePath": [
      "core",
      "upstream-selector",
      "policy",
      "downstream-selector",
      "access"
    ],
    "lastHops": [
      "edge-example-router-access-client",
      "edge-example-router-access-dmz"
    ]
  },
  {
    "example": "tri-site-s-router-overlay-egress",
    "enterprise": "esp",
    "site": "home",
    "relationId": "allow-site-overlay-icmp-anywhere",
    "stagePath": [
      "core",
      "access",
      "downstream-selector",
      "policy",
      "downstream-selector",
      "access"
    ],
    "lastHops": [
      "home-example-router-access-admin",
      "home-example-router-access-client",
      "home-example-router-access-dmz",
      "home-example-router-access-hostile",
      "home-example-router-access-mgmt",
      "home-example-router-access-streaming"
    ]
  },
  {
    "example": "tri-site-s-router-overlay-egress",
    "enterprise": "esp",
    "site": "home",
    "relationId": "allow-site-wan-icmp-anywhere",
    "stagePath": [
      "core",
      "upstream-selector",
      "policy",
      "downstream-selector",
      "access"
    ],
    "lastHops": [
      "home-example-router-access-admin",
      "home-example-router-access-client",
      "home-example-router-access-dmz",
      "home-example-router-access-hostile",
      "home-example-router-access-mgmt",
      "home-example-router-access-streaming",
      "home-example-router-access-admin",
      "home-example-router-access-client",
      "home-example-router-access-dmz",
      "home-example-router-access-hostile",
      "home-example-router-access-mgmt",
      "home-example-router-access-streaming"
    ]
  },
  {
    "example": "tri-site-s-router-overlay-egress",
    "enterprise": "esp",
    "site": "lab",
    "relationId": "allow-lab-overlay-icmp-anywhere",
    "stagePath": [
      "core",
      "access",
      "downstream-selector",
      "policy",
      "downstream-selector",
      "access"
    ],
    "lastHops": [
      "lab-example-router-access-admin",
      "lab-example-router-access-client",
      "lab-example-router-access-dmz",
      "lab-example-router-access-hostile",
      "lab-example-router-access-mgmt",
      "lab-example-router-access-streaming"
    ]
  },
  {
    "example": "tri-site-s-router-overlay-egress",
    "enterprise": "esp",
    "site": "lab",
    "relationId": "allow-lab-wan-icmp-anywhere",
    "stagePath": [
      "core",
      "upstream-selector",
      "policy",
      "downstream-selector",
      "access"
    ],
    "lastHops": [
      "lab-example-router-access-admin",
      "lab-example-router-access-client",
      "lab-example-router-access-dmz",
      "lab-example-router-access-hostile",
      "lab-example-router-access-mgmt",
      "lab-example-router-access-streaming"
    ]
  }
]
JSON

diff -u "${expected_json}" "${actual_json}"

invalid_wildcard_input="${tmp_dir}/invalid-wildcard-target.nix"
cat >"${invalid_wildcard_input}" <<EOF
let
  base = import "${labs_path}/examples/single-wan-with-nebula-any-to-any-fw/intent.nix";
in
base
// {
  esp0xdeadbeef =
    base.esp0xdeadbeef
    // {
      "site-a" =
        base.esp0xdeadbeef."site-a"
        // {
          communicationContract =
            base.esp0xdeadbeef."site-a".communicationContract
            // {
              relations =
                (base.esp0xdeadbeef."site-a".communicationContract.relations or [ ])
                ++ [
                  {
                    id = "invalid-adjacent-wildcard-token";
                    priority = 999;
                    from = { kind = "tenant"; name = "client"; };
                    to = "*";
                    trafficType = "any";
                    action = "allow";
                  }
                ];
            };
        };
    };
}
EOF

set +e
invalid_output="$(nix run "$ROOT#compile" -- "${invalid_wildcard_input}" 2>&1)"
invalid_rc=$?
set -e

if [[ "${invalid_rc}" -eq 0 ]]; then
  echo "FAIL invalid-adjacent-wildcard-token: expected relation.to shape failure" >&2
  exit 1
fi

if ! grep -q "E_CONTRACT_TARGET_SHAPE" <<<"${invalid_output}"; then
  echo "FAIL invalid-adjacent-wildcard-token: missing E_CONTRACT_TARGET_SHAPE" >&2
  printf '%s\n' "${invalid_output}" >&2
  exit 1
fi

echo "PASS network-labs-wildcard-traffic-paths"
