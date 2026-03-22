# TODO — Preserve `communicationContract.interfaceTags` in compiler output

## Problem

The compiler input contains explicit interface tag metadata under:

`communicationContract.interfaceTags`

Example input shape:

```nix
communicationContract = {
  interfaceTags = {
    tenant-mgmt = "mgmt";
    external-east-west = "east-west";
  };

  relations = [
    {
      id = "allow-mgmt-to-overlay-east-west";
      action = "allow";
      from = { kind = "tenant"; name = "mgmt"; };
      to = { kind = "external"; name = "east-west"; };
      trafficType = "any";
      priority = 100;
    }
  ];

  services = [ ];
  trafficTypes = [ ];
};

However, the compiled site output drops interfaceTags.

Observed behavior:

meta.provenance.originalInputs.*.*.communicationContract.interfaceTags is present
sites.*.*.communicationContract.interfaceTags is missing

This proves the loss happens in the compiler normalization / output assembly path.

Required behavior

When the compiler receives:

communicationContract.interfaceTags = { ... };

it must preserve that field in compiled output at:

sites.<enterprise>.<site>.communicationContract.interfaceTags

The compiler must not silently discard this field while rewriting:

relations -> allowedRelations
normalized site objects
signed / emitted compiler JSON
Acceptance criteria
 communicationContract.interfaceTags is present in compiled sites.*.* output
 values are preserved exactly
 existing relations -> allowedRelations rewrite still works
 services and trafficTypes are unchanged

 compiled output includes:

{
  "sites": {
    "<enterprise>": {
      "<site>": {
        "communicationContract": {
          "interfaceTags": {
            "tenant-mgmt": "mgmt",
            "external-east-west": "east-west"
          }
        }
      }
    }
  }
}
Likely fix area

Investigate the compiler code that reconstructs or normalizes communicationContract.

The bug is likely caused by one of these patterns:

explicit attrset reconstruction that only copies:
allowedRelations
services
trafficTypes
field whitelist that omits interfaceTags
normalization code that removes relations but forgets to carry forward sibling fields
Required implementation change

Where the compiler normalizes communicationContract, ensure it does:

preserve all required sibling fields
explicitly carry interfaceTags
only rewrite relations into allowedRelations
do not require downstream repos to restore lost contract metadata from provenance

Target behavior should be equivalent to:

communicationContract =
  (builtins.removeAttrs contract [ "relations" ])
  // {
    allowedRelations = ...;
    interfaceTags = contract.interfaceTags or { };
  };

The exact implementation can differ, but the emitted structure must preserve the field.

Tests to add
 fixture with communicationContract.interfaceTags
 compiler assertion that sites.*.*.communicationContract.interfaceTags exists
 assertion that emitted values exactly match input values
 regression test proving provenance contains the field and normalized sites also contains it
 regression test proving field is not lost when overlays / external relations are present
Minimal regression check

After the fix, this must return success:

jq -e '
  .sites
  | to_entries[]
  | .value
  | to_entries[]
  | .value.communicationContract.interfaceTags
  | type == "object"
' output-compiler-signed.json

And this should show the field exists in both places:

jq '
  {
    provenance: (
      .meta.provenance.originalInputs
      | to_entries
      | map({
          enterprise: .key,
          sites: (
            .value
            | to_entries
            | map({
                site: .key,
                interfaceTags: .value.communicationContract.interfaceTags
              })
          )
        })
    ),
    compiled: (
      .sites
      | to_entries
      | map({
          enterprise: .key,
          sites: (
            .value
            | to_entries
            | map({
                site: .key,
                interfaceTags: .value.communicationContract.interfaceTags
              })
          )
        })
    )
  }
' output-compiler-signed.json
Definition of done
 input contains communicationContract.interfaceTags
 compiler output under sites.*.*.communicationContract.interfaceTags also contains it
 field values are unchanged
 downstream solver no longer depends on provenance to recover missing interface tags
 downstream network-control-plane-model no longer fails for valid inputs because tags were dropped by the compiler
