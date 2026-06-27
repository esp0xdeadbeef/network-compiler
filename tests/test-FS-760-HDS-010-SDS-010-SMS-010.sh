#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-760-HDS-010-SDS-010-SMS-010
# GAMP-SCOPE: software-module-test

ROOT="${NETWORK_COMPILER_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

if command -v jq >/dev/null 2>&1; then
  jq_cmd=(jq)
else
  jq_cmd=(nix run nixpkgs#jq --)
fi

archive_json="$(mktemp)"
output_json="$(mktemp)"
trap 'rm -f "$archive_json" "$output_json"' EXIT

nix flake archive --json "path:${ROOT}" >"$archive_json"

labs_root="${NETWORK_LABS_ROOT:-}"
if [[ -z "$labs_root" ]]; then
  labs_root="$("${jq_cmd[@]}" -er '.inputs["network-labs"].path' "$archive_json")"
fi

intent="${labs_root}/GAMP/HAT/emulated-isp-residential-testnet/intent.nix"
if [[ ! -f "$intent" ]]; then
  echo "missing HAT intent fixture: $intent" >&2
  exit 1
fi

nix run "$ROOT#compile" -- "$intent" >"$output_json"

"${jq_cmd[@]}" -e '
  def has_surface($protocol; $transport; $port):
    any(.discovery.surfaces[]; .protocol == $protocol and .transport == $transport and .port == $port);

  def has_dial_surface:
    any(.discovery.surfaces[]; .protocol == "dial" and .transport == "tcp" and .service == "hat-receiver-control");

  def has_denial($boundary):
    (.discovery.deniedByDesign | index($boundary)) != null;

  def check_site($site; $provider):
    .sites.esp0xdeadbeef[$site].accessSpaceDiscovery.sharedServicePolicyAtoms as $atoms
    | ([$atoms[] | select(.id == "fs760-receiver-discovery-policy")] | length == 1)
    and (
      $atoms[]
      | select(.id == "fs760-receiver-discovery-policy")
      | .sms == "FS-760-HDS-010-SDS-010-SMS-010"
        and .service == "hat-receiver-discovery"
        and .serviceClass == "media-receiver"
        and .provider == $provider
        and .requesterScopes == ["trusted"]
        and .controllerScopes == ["trusted"]
        and .responderScope == "iot"
        and .receiverScope == "iot"
        and .payload == { authorized: false, inferredFromDiscovery: false }
        and .discovery.allowed == true
        and .discovery.decision == "discovery-only"
        and .discovery.protocols == ["mdns", "ssdp", "dial"]
        and has_surface("mdns"; "udp"; 5353)
        and has_surface("ssdp"; "udp"; 1900)
        and has_dial_surface
        and has_denial("controller-payload")
        and has_denial("reverse-initiation")
        and has_denial("guest-to-trusted")
        and has_denial("media-to-management")
        and has_denial("multicast-flooding")
        and .source.sourcePath == ["communicationContract", "sharedServicePolicyAtoms", 4]
    );

  check_site("site-a"; "nixos-receiver01")
  and check_site("site-b"; "clab-receiver01")
  and any(
    .sites.esp0xdeadbeef."site-a".sourceAudit.behavior[];
    .outputPath == ["accessSpaceDiscovery", "sharedServicePolicyAtoms", 1]
    and .sourcePath == ["communicationContract", "sharedServicePolicyAtoms", 4]
  )
  and any(
    .sites.esp0xdeadbeef."site-b".sourceAudit.behavior[];
    .outputPath == ["accessSpaceDiscovery", "sharedServicePolicyAtoms", 1]
    and .sourcePath == ["communicationContract", "sharedServicePolicyAtoms", 4]
  )
' "$output_json" >/dev/null

echo "PASS fs760-receiver-discovery-policy-contract"
