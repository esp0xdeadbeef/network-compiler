#!/usr/bin/env bash
set -euo pipefail

ROOT="${NETWORK_COMPILER_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

nix eval --impure --expr '
let
  pkgs = import <nixpkgs> { };
  lib = pkgs.lib;
  stageLinks = import '"$ROOT"'/lib/correctness/topology/stage-links.nix { inherit lib; };

  roles = [
    "access"
    "downstream-selector"
    "policy"
    "upstream-selector"
    "core"
  ];

  stageIndex = {
    access = 0;
    downstream-selector = 1;
    policy = 2;
    upstream-selector = 3;
    core = 4;
  };

  abs = n: if n < 0 then -n else n;

  evalPair =
    leftRole: rightRole:
    let
      nodes = {
        left.role = leftRole;
        right.role = rightRole;
      };
      result = builtins.tryEval (
        stageLinks.validateCanonicalStageLinks "matrix-site" nodes [ ] [
          [ "left" "right" ]
        ]
      );
      expected = abs (stageIndex.${leftRole} - stageIndex.${rightRole}) == 1;
    in
    {
      pair = "${leftRole}->${rightRole}";
      inherit expected;
      actual = result.success && result.value;
      ok = expected == (result.success && result.value);
    };

  pairResults =
    builtins.concatMap
      (leftRole: map (rightRole: evalPair leftRole rightRole) roles)
      roles;

  failures = builtins.filter (row: !row.ok) pairResults;

  baseNodes = {
    access.role = "access";
    downstream.role = "downstream-selector";
    policy.role = "policy";
    upstream.role = "upstream-selector";
    core.role = "core";
  };

  baseResult = builtins.tryEval (
    stageLinks.validateCanonicalStageLinks "base-site" baseNodes [ ] [
      [ "access" "downstream" ]
      [ "downstream" "policy" ]
      [ "policy" "upstream" ]
      [ "upstream" "core" ]
    ]
  );

  reverseBaseResult = builtins.tryEval (
    stageLinks.validateCanonicalStageLinks "base-site" baseNodes [ ] [
      [ "downstream" "access" ]
      [ "policy" "downstream" ]
      [ "upstream" "policy" ]
      [ "core" "upstream" ]
    ]
  );

  sharedAttachmentResult = builtins.tryEval (
    stageLinks.validateCanonicalStageLinks "provider-handoff-site" {
      access = {
        role = "access";
        attachments = [
          {
            kind = "tenant";
            name = "provider-handoff-a";
          }
        ];
      };
      core = {
        role = "core";
        attachments = [
          {
            kind = "tenant";
            name = "provider-handoff-a";
          }
        ];
      };
    } [ ] [
      [ "access" "core" ]
    ]
  );

  mismatchedAttachmentResult = builtins.tryEval (
    stageLinks.validateCanonicalStageLinks "provider-handoff-site" {
      access = {
        role = "access";
        attachments = [
          {
            kind = "tenant";
            name = "provider-handoff-a";
          }
        ];
      };
      core = {
        role = "core";
        attachments = [
          {
            kind = "tenant";
            name = "provider-handoff-b";
          }
        ];
      };
    } [ ] [
      [ "access" "core" ]
    ]
  );

  total = builtins.length pairResults;
  valid = builtins.length (builtins.filter (row: row.expected) pairResults);
  invalid = total - valid;
in
if failures != [ ] then
  builtins.throw ("canonical stage link matrix mismatch: " + builtins.toJSON failures)
else if !(baseResult.success && baseResult.value) then
  builtins.throw "canonical base scheme failed"
else if !(reverseBaseResult.success && reverseBaseResult.value) then
  builtins.throw "canonical base scheme failed when links were listed in reverse endpoint order"
else if !(sharedAttachmentResult.success && sharedAttachmentResult.value) then
  builtins.throw "shared core/access attachment should be accepted for provider handoff"
else if mismatchedAttachmentResult.success then
  builtins.throw "mismatched core/access attachment should not be accepted"
else
  {
    inherit total valid invalid;
    base = true;
    reverseBase = true;
    sharedAttachment = true;
    mismatchedAttachmentRejected = true;
  }
' >/dev/null

echo "PASS canonical-stage-link-matrix"
