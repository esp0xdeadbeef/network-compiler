#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if command -v jq >/dev/null 2>&1; then
  jq_cmd=(jq)
else
  jq_cmd=(nix run nixpkgs#jq --)
fi

archive_json="$(mktemp)"
trap 'rm -f "${archive_json}"' EXIT

nix flake archive --json "path:${repo_root}" > "${archive_json}"

labs_root="${NETWORK_LABS_ROOT:-}"
if [[ -z "${labs_root}" ]]; then
  labs_root="$(
    "${jq_cmd[@]}" -er '.inputs["network-labs"].path' "${archive_json}"
  )"
fi

examples_root="${labs_root}/examples"
[[ -d "${examples_root}" ]] || {
  echo "missing network-labs examples root: ${examples_root}" >&2
  exit 1
}
labs_profiles_root="${labs_root}/labs"

jobs="${NETWORK_TEST_JOBS:-${TEST_JOBS:-48}}"
if ! [[ "${jobs}" =~ ^[1-9][0-9]*$ ]]; then
  echo "invalid NETWORK_TEST_JOBS/TEST_JOBS value: ${jobs}" >&2
  exit 1
fi

compile_one() {
  local kind="$1"
  local path="$2"
  local rel="$3"

  echo "checking network-labs ${kind}: ${rel}"
  nix run "${repo_root}#compile" -- "${path}" | jq -e 'has("sites") and has("meta")' >/dev/null
}

pids=()
labels=()
failures=0

wait_for_slot() {
  local pid label rc
  while ((${#pids[@]} >= jobs)); do
    pid="${pids[0]}"
    label="${labels[0]}"
    pids=("${pids[@]:1}")
    labels=("${labels[@]:1}")
    set +e
    wait "${pid}"
    rc=$?
    set -e
    if ((rc != 0)); then
      echo "FAIL network-labs compile: ${label} (rc=${rc})" >&2
      failures=$((failures + 1))
    fi
  done
}

start_one() {
  local kind="$1"
  local path="$2"
  local rel="$3"

  wait_for_slot
  compile_one "${kind}" "${path}" "${rel}" &
  pids+=("$!")
  labels+=("${kind}:${rel}")
}

found=0
while IFS= read -r -d '' intent_path; do
  found=1
  rel="${intent_path#"${examples_root}/"}"
  start_one "example" "${intent_path}" "${rel%/intent.nix}"
done < <(find "${examples_root}" -mindepth 2 -maxdepth 2 -name intent.nix -print0 | sort -z)

if [[ -d "${labs_profiles_root}" ]]; then
  while IFS= read -r -d '' lab_intent_path; do
    found=1
    rel="${lab_intent_path#"${labs_root}/"}"
    start_one "lab intent" "${lab_intent_path}" "${rel%/intent.nix}"
  done < <(find "${labs_profiles_root}" -mindepth 3 -maxdepth 3 -name intent.nix -print0 | sort -z)

  while IFS= read -r -d '' compiler_input_path; do
    found=1
    rel="${compiler_input_path#"${labs_root}/"}"
    start_one "lab compiler input" "${compiler_input_path}" "${rel%/getCompilerInput.nix}"
  done < <(find "${labs_profiles_root}" -mindepth 3 -maxdepth 3 -name getCompilerInput.nix -print0 | sort -z)
fi

for idx in "${!pids[@]}"; do
  set +e
  wait "${pids[$idx]}"
  rc=$?
  set -e
  if ((rc != 0)); then
    echo "FAIL network-labs compile: ${labels[$idx]} (rc=${rc})" >&2
    failures=$((failures + 1))
  fi
done

if ((failures > 0)); then
  echo "FAIL network-labs compile sweep: ${failures} job(s) failed" >&2
  exit 1
fi

if (( found == 0 )); then
  echo "no network-labs examples or labs found under ${labs_root}" >&2
  exit 1
fi
