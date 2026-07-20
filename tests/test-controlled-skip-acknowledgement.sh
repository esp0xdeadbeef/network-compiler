#!/usr/bin/env bash
# GAMP-ID: FS-166-HDS-010-SDS-010-SMS-010
# GAMP-SCOPE: software-module-test; repository-owned skip acknowledgement
set -euo pipefail

ROOT="${NETWORK_COMPILER_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

nix eval --impure --json --expr '
  let
    api = (builtins.getFlake "path:'"$ROOT"'").libBySystem.${builtins.currentSystem};
    skip = api.controlledSkip;
    acknowledgement = api.controlledSkipAcknowledgement {
      traceId = "FS-166-HDS-010-SDS-010-SMS-010";
      declaredRepository = skip.repository;
      lockedRepositoryRevision = skip.repositoryRevision;
      declaredStageIndex = skip.stageIndex;
      declaredNormalInputContract = skip.normalInputContract;
      replacementContract = "network-forwarding-model-input/v1";
      expectedReplacementContract = "network-forwarding-model-input/v1";
      declaredFirstActiveBoundary = "network-forwarding-model";
      expectedFirstActiveBoundary = "network-forwarding-model";
      reason = "controlled replacement starts at NFM input";
      declaredPreviousStage = skip.previousStage;
      declaredNextStage = skip.nextStage;
      replacementIdentity = "fixture-nfm-input";
      replacementDigest = builtins.hashString "sha256" "fixture-nfm-input";
    };
  in
  assert acknowledgement.payloadAccessed == false;
  assert acknowledgement.transformationStarted == false;
  assert acknowledgement.acknowledgementCount == 1;
  assert builtins.stringLength acknowledgement.acknowledgementDigest == 64;
  acknowledgement
' >/dev/null

set +e
diagnostic="$({ nix eval --impure --json --expr '
  let
    api = (builtins.getFlake "path:'"$ROOT"'").libBySystem.${builtins.currentSystem};
    skip = api.controlledSkip;
  in
  api.controlledSkipAcknowledgement {
    traceId = "FS-166-HDS-010-SDS-010-SMS-010";
    declaredRepository = skip.repository;
    lockedRepositoryRevision = skip.repositoryRevision;
    declaredStageIndex = skip.stageIndex;
    declaredNormalInputContract = skip.normalInputContract;
    replacementContract = "network-forwarding-model-input/v1";
    expectedReplacementContract = "network-forwarding-model-input/v1";
    declaredFirstActiveBoundary = "network-forwarding-model";
    expectedFirstActiveBoundary = "network-forwarding-model";
    reason = "seeded payload-access negative";
    declaredPreviousStage = skip.previousStage;
    declaredNextStage = skip.nextStage;
    replacementIdentity = "fixture-nfm-input";
    replacementDigest = builtins.hashString "sha256" "fixture-nfm-input";
    payloadAccessed = true;
  }
'; } 2>&1)"
status=$?
set -e

[[ "$status" -ne 0 ]]
grep -Fq 'NS_SKIP_PAYLOAD_ACCESSED: /payloadAccessed:' <<<"$diagnostic"

echo "PASS controlled-skip-acknowledgement network-compiler"
