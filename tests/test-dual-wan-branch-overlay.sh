#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
example_root="${repo_root}/../network-labs/examples"

fail() { echo "$1" >&2; exit 1; }

run_one() {
  local example_name="$1"
  local intent_path="${example_root}/${example_name}/intent.nix"

  [[ -f "${intent_path}" ]] || fail "missing intent.nix: ${intent_path}"

  local output_json
  output_json="$(mktemp)"
  trap 'rm -f "'"${output_json}"'"' RETURN

  nix run "${repo_root}#compile" -- "${intent_path}" > "${output_json}"

  OUTPUT_JSON="${output_json}" nix eval --impure --expr '
    let
      data = builtins.fromJSON (builtins.readFile (builtins.getEnv "OUTPUT_JSON"));
      siteA = data.sites.enterpriseA."site-a";
      siteB = data.sites.enterpriseB."site-b";
      overlayA = builtins.head data.meta.provenance.originalInputs.enterpriseA."site-a".transport.overlays;
      overlayB = builtins.head data.meta.provenance.originalInputs.enterpriseB."site-b".transport.overlays;
    in
      overlayA.name == "east-west"
      && overlayA.terminateOn == "s-router-core-isp-b"
      && overlayA.peerSite == "enterpriseB.site-b"
      && overlayB.name == "east-west"
      && overlayB.terminateOn == "b-router-core"
      && overlayB.peerSite == "enterpriseA.site-a"
      && builtins.any
        (r: (r.source.id or "") == "allow-core-tenants-to-east-west")
        siteA.relations
      && builtins.any
        (r: (r.source.id or "") == "allow-branch-to-east-west")
        siteB.relations
  ' >/dev/null || fail "FAIL ${example_name}: compile validation failed"

  echo "PASS ${example_name}"
  rm -f "${output_json}"
  trap - RETURN
}

run_one "dual-wan-branch-overlay"
run_one "dual-wan-branch-overlay-bgp"
