#!/usr/bin/env bash
# GAMP-ID: FS-560-HDS-010-SDS-020-SMS-010
# GAMP-SCOPE: software-module-test
set -euo pipefail

repo_root="${NETWORK_COMPILER_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"

REPO_ROOT="${repo_root}" nix eval --impure --raw --expr '
  let
    repoRoot = builtins.getEnv "REPO_ROOT";
    flake = builtins.getFlake ("path:" + repoRoot);
    lib = flake.inputs.nixpkgs.lib;
    build = import (repoRoot + "/lib/stages/dns-contract/default.nix") { inherit lib; };
    relation = id: requester: authority: {
      authority = { service = authority; records = [ "modeled-local-data" ]; };
      requester = {
        service = requester;
        allowedNamespaces = [ "lan." "1.168.192.in-addr.arpa." ];
        recursion = false;
        publicFallback = false;
      };
      relation = { inherit id; };
      providerPolicy = { source = requester; action = "refuse_non_local"; };
      lateralPolicy = {
        source = requester;
        target = authority;
        localData = true;
        recursion = false;
        transitiveEgress = false;
        action = "refuse_non_local";
      };
    };
    declared = {
      enterprise = "example";
      siteName = "site-a";
      localDnsSharingIntents = [
        (relation "share-a-to-b" "dns-a" "dns-b")
        (relation "share-b-to-a" "dns-b" "dns-a")
      ];
    };
    output = build "site-a" declared {
      a.role = "access";
      b.role = "access";
    } { };
    duplicate = build "site-a" (declared // {
      localDnsSharingIntents = [
        (relation "duplicate" "dns-a" "dns-b")
        (relation "duplicate" "dns-b" "dns-a")
      ];
    }) {
      a.role = "access";
      b.role = "access";
    } { };
    require = condition: message: if condition then true else throw message;
  in
    if
      require (builtins.length output.localSharingRelations == 2)
        "compiler did not preserve both directional namespace-sharing relations"
      && require (output.localSharing == null)
        "legacy single-relation alias remained authoritative for a plural contract"
      && require (builtins.any (entry: entry.code == "DNS_LOCAL_SHARING_RELATION_DUPLICATE") duplicate.warnings)
        "duplicate local namespace relation identities did not fail closed"
      && require (duplicate.localSharingRelations == [ ])
        "duplicate local namespace relations produced partial output"
    then "ok" else throw "unreachable"
' >/dev/null

echo "PASS FS-560 local namespace sharing plural normalization"
