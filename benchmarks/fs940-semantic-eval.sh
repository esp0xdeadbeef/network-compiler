#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

threshold_ms="${COMPILER_BENCH_THRESHOLD_MS:-3000}"
if ! [[ "${threshold_ms}" =~ ^[0-9]+$ ]] || [ "${threshold_ms}" -lt 1 ]; then
  echo "FAIL fs940-semantic-eval: COMPILER_BENCH_THRESHOLD_MS must be a positive integer" >&2
  exit 1
fi

repo_revision="$(git -C "${repo_root}" rev-parse HEAD 2>/dev/null || echo unknown)"
repo_dirty=false
if ! git -C "${repo_root}" diff --quiet >/dev/null 2>&1 || ! git -C "${repo_root}" diff --cached --quiet >/dev/null 2>&1; then
  repo_dirty=true
fi
locked_revisions="$(jq -r '[.nodes | to_entries[] | select(.value.locked.rev?) | "\(.key)=\(.value.locked.rev)"] | join(",")' "${repo_root}/flake.lock")"
host_class="$(uname -m)-$(uname -s | tr '[:upper:]' '[:lower:]')"
excluded_runtime_stages="nix-build,container-image-build,vm-deployment,containerlab-deployment,boot,live-packet-validation,provider-calls,cache-misses"

archive_json="$(mktemp)"
trap 'rm -f "${archive_json}"' EXIT
nix flake archive --json "path:${repo_root}" >"${archive_json}"
labs_root="$(jq -er '.inputs["network-labs"].path' "${archive_json}")"

examples=(
  "hat-emulated-isp-residential-testnet:${labs_root}/GAMP/HAT/emulated-isp-residential-testnet/intent.nix"
  "sat-controlled-baseline:${labs_root}/GAMP/SAT/intent.nix"
)

failed=0

for example_spec in "${examples[@]}"; do
  example="${example_spec%%:*}"
  intent="${example_spec#*:}"
  if [[ ! -f "${intent}" ]]; then
    echo "FAIL fs940-semantic-eval ${example}: missing ${intent}" >&2
    failed=1
    continue
  fi

  start_ms="$(date +%s%3N)"
  if ! summary="$(
    timeout "$((threshold_ms / 1000 + 20))" \
      nix eval \
        --extra-experimental-features 'nix-command flakes' \
        --impure \
        --json \
        --expr "
          let
            flake = builtins.getFlake \"path:${repo_root}\";
            raw = import \"${intent}\";
            input = if builtins.isFunction raw then raw { } else raw;
            compiled = flake.libBySystem.x86_64-linux.compile input;
            siteValues = builtins.concatMap
              (enterpriseName:
                map
                  (siteName: (builtins.getAttr siteName (builtins.getAttr enterpriseName input)))
                  (builtins.attrNames (builtins.getAttr enterpriseName input)))
              (builtins.attrNames input);
            compiledSites = builtins.concatMap
              (enterpriseName:
                map
                  (siteName: builtins.getAttr siteName (builtins.getAttr enterpriseName compiled.sites))
                  (builtins.attrNames (builtins.getAttr enterpriseName compiled.sites)))
              (builtins.attrNames compiled.sites);
          in
          {
            upstream = {
              enterprises = builtins.length (builtins.attrNames input);
              sites = builtins.length siteValues;
              nodes = builtins.foldl' (acc: site: acc + builtins.length (builtins.attrNames (site.topology.nodes or { }))) 0 siteValues;
              links = builtins.foldl' (acc: site: acc + builtins.length (site.topology.links or [ ])) 0 siteValues;
              relations = builtins.foldl' (acc: site: acc + builtins.length (site.communicationContract.relations or [ ])) 0 siteValues;
              services = builtins.foldl' (acc: site: acc + builtins.length (site.communicationContract.services or [ ])) 0 siteValues;
            };
            downstream = {
              sites = builtins.length compiledSites;
              nodes = builtins.foldl' (acc: site: acc + builtins.length (builtins.attrNames ((site.topology or { }).nodes or site.nodes or { }))) 0 compiledSites;
              relations = builtins.foldl' (acc: site: acc + builtins.length (site.relations or [ ])) 0 compiledSites;
              trafficPaths = builtins.foldl' (acc: site: acc + builtins.length (site.trafficPaths or [ ])) 0 compiledSites;
              overlayAttachments = builtins.foldl' (acc: site: acc + builtins.length (builtins.attrNames (site.overlayAttachments or { }))) 0 compiledSites;
            };
          }
        "
  )"; then
    end_ms="$(date +%s%3N)"
    elapsed_ms=$((end_ms - start_ms))
    echo "BENCH fs940 stage=compiler example=${example} status=FAIL elapsed_ms=${elapsed_ms} threshold_ms=${threshold_ms} repo_revision=${repo_revision} repo_dirty=${repo_dirty} locked_revisions=${locked_revisions} timing_method=date_ms host_class=${host_class} cache_state=warm-required command=nix-eval-libBySystem.compile upstream_cardinality=unknown downstream_cardinality=unknown excluded_runtime_stages=${excluded_runtime_stages}" >&2
    failed=1
    continue
  fi
  end_ms="$(date +%s%3N)"
  elapsed_ms=$((end_ms - start_ms))

  status=PASS
  if [ "${elapsed_ms}" -gt "${threshold_ms}" ]; then
    status=FAIL
    failed=1
  fi

  upstream_cardinality="$(jq -r '.upstream | to_entries | map("\(.key):\(.value)") | join(",")' <<<"${summary}")"
  downstream_cardinality="$(jq -r '.downstream | to_entries | map("\(.key):\(.value)") | join(",")' <<<"${summary}")"

  echo "BENCH fs940 stage=compiler example=${example} status=${status} elapsed_ms=${elapsed_ms} threshold_ms=${threshold_ms} repo_revision=${repo_revision} repo_dirty=${repo_dirty} locked_revisions=${locked_revisions} timing_method=date_ms host_class=${host_class} cache_state=warm-required command=nix-eval-libBySystem.compile upstream_cardinality=${upstream_cardinality} downstream_cardinality=${downstream_cardinality} excluded_runtime_stages=${excluded_runtime_stages}"
done

exit "${failed}"
