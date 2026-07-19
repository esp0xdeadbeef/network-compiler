#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-230-HDS-010-SDS-010-SMS-040
# GAMP-SCOPE: compiler construction check for an explicitly authorized ingress-only site

root="${NETWORK_COMPILER_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

ROOT="${root}" nix eval --impure --expr '
let
  root = builtins.getEnv "ROOT";
  flake = builtins.getFlake ("path:" + root);
  compile = flake.libBySystem.${builtins.currentSystem}.compileValue;
  trace = "FS-230-HDS-010-SDS-010-SMS-040";
  relation = {
    id = "${trace}__lab-wan-to-nebula-ipv6";
    priority = 100;
    action = "allow";
    from = {
      kind = "external";
      uplinks = [ "lab-wan" ];
    };
    to = {
      kind = "service";
      name = "nebula-lab";
    };
    trafficType = "nebula-ipv6";
    returnBehavior = "stateful-return";
    publicIngressTupleAuthority = {
      family = "ipv6";
      targetService = "nebula-lab";
      targetPort = 4242;
      tuples = [
        {
          protocol = "udp";
          publicPort = 4242;
        }
      ];
      translationMode = "none";
      sourcePreservation = "preserve-source";
      returnBehavior = "stateful-return";
    };
  };
  site = {
    communicationContract = {
      interfaceTags = {
        external-lab-wan = "lab-wan";
        service-nebula-lab = "nebula-lab";
        tenant-lab-dmz = "lab-dmz";
      };
      relations = [ relation ];
      services = [
        {
          name = "nebula-lab";
          providers = [ "nebula-lab-endpoint" ];
          trafficType = "nebula-ipv6";
        }
      ];
      trafficTypes = [
        {
          name = "nebula-ipv6";
          match = [
            {
              family = "ipv6";
              proto = "udp";
              dports = [ 4242 ];
            }
          ];
        }
      ];
    };
    ownership = {
      prefixes = [
        {
          kind = "tenant";
          name = "lab-dmz";
          ipv4 = "10.2.30.0/24";
          ipv6 = "fd42:230:40::/64";
        }
      ];
      endpoints = [
        {
          kind = "host";
          name = "nebula-lab-endpoint";
          tenant = "lab-dmz";
        }
      ];
    };
    pools = {
      loopback = {
        ipv4 = "10.23.0.0/24";
        ipv6 = "fd42:230:ff::/118";
      };
      p2p = {
        ipv4 = "10.23.255.0/24";
        ipv6 = "fd42:230:fe::/118";
      };
    };
    topology = {
      links = [
        [ "access-dmz" "downstream-selector" ]
        [ "downstream-selector" "policy" ]
        [ "policy" "upstream-selector" ]
        [ "upstream-selector" "core-lab-wan" ]
      ];
      nodes = {
        access-dmz = {
          role = "access";
          attachments = [
            {
              kind = "tenant";
              name = "lab-dmz";
            }
          ];
        };
        downstream-selector.role = "downstream-selector";
        policy.role = "policy";
        upstream-selector.role = "upstream-selector";
        core-lab-wan = {
          role = "core";
          uplinks.lab-wan = {
            ipv4 = [ "0.0.0.0/0" ];
            ipv6 = [ "::/0" ];
          };
        };
      };
    };
  };
  input.mini-smt.${trace} = site;
  compiled = compile input;
  compiledSite = compiled.sites.mini-smt.${trace};
  normalized = builtins.head compiledSite.relations;
  hasInventedEgress = builtins.any (
    candidate:
    builtins.elem (candidate.from.kind or null) [ "tenant" "tenant-set" ]
    && (candidate.to.kind or null) == "external"
  ) compiledSite.relations;
  withoutAuthority = builtins.tryEval (
    builtins.deepSeq (compile {
      mini-smt.${trace} = site // {
        communicationContract = site.communicationContract // {
          relations = [ (builtins.removeAttrs relation [ "publicIngressTupleAuthority" ]) ];
        };
      };
    }) true
  );
  deniedIngress = builtins.tryEval (
    builtins.deepSeq (compile {
      mini-smt.${trace} = site // {
        communicationContract = site.communicationContract // {
          relations = [ (relation // { action = "deny"; }) ];
        };
      };
    }) true
  );
in
  if normalized.source.id != relation.id then
    throw "explicit ingress relation was not preserved"
  else if normalized.publicIngressTupleAuthority != relation.publicIngressTupleAuthority then
    throw "public-ingress tuple authority changed during compilation"
  else if hasInventedEgress then
    throw "compiler invented internal-to-external authority for ingress-only site"
  else if withoutAuthority.success then
    throw "external-to-service relation without publicIngressTupleAuthority satisfied ingress-only gate"
  else if deniedIngress.success then
    throw "denied public ingress satisfied ingress-only gate"
  else
    true
' >/dev/null

printf 'PASS FS-230-HDS-010-SDS-010-SMS-040 compiler ingress-only public authority\n'
