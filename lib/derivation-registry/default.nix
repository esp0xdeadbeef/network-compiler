{ lib }:

# FS-172-HDS-010-SDS-010: Derived-Fact Source Necessity.
#
# The registry is the single authority for which facts are *derivable*. It does
# not restate the rules themselves: the Derivation-Rule Registry Map in
# FS-172-HDS-010-SDS-010 owns each rule's inputs and output, and this module
# references it by rule identity. Adding a derived fact means adding a row there;
# the only change here is a reference to that row.
#
# Three refusals live here, each raised by the owning deriving layer named in the
# registry rather than by a downstream consumer:
#
#   * a derived fact no rule produces      -> unsubstantiated derivation
#   * two rules claiming one derived fact  -> duplicate rule identity
#   * a rule that default-fills a fact it
#     does not determine                   -> default-fill rejection
#   * a derivable field supplied as input  -> duplicate writer
#   * a rule and a supplied source value
#     that disagree                        -> rule/source disagreement
#
# Nothing in this module creates policy or authority. It decides *where a value
# comes from*, never whether the value is allowed.

let
  util = import ../correctness/util.nix { inherit lib; };
  inherit (util) ensure;

  isNonEmptyString = value: builtins.isString value && value != "";

  require =
    cond: code: path: site: message: hints:
    ensure cond {
      inherit code;
      inherit path site message hints;
    };

  inherit (import ./data.nix) ruleIdentities defaultEntries;


  # SN: two entries claiming to produce the same derived fact is a duplicate rule
  # identity. Neither silently wins.
  ensureNoDuplicateIdentities =
    site: entries:
    let
      facts = map (entry: entry.derivedFact) entries;
      duplicates = lib.filter (fact: builtins.length (lib.filter (f: f == fact) facts) > 1) (
        lib.unique facts
      );
      ids = map (entry: entry.ruleId) entries;
      duplicateIds = lib.filter (id: builtins.length (lib.filter (i: i == id) ids) > 1) (lib.unique ids);
    in
    require
      (duplicates == [ ] && duplicateIds == [ ])
      "E_DERIVATION_RULE_IDENTITY_DUPLICATE"
      [ "derivationRegistry" ]
      site
      (
        if duplicateIds != [ ] then
          "duplicate rule identity: ${builtins.concatStringsSep ", " duplicateIds}"
        else
          "two rules claim the same derived fact: ${builtins.concatStringsSep ", " duplicates}"
      )
      [
        "Each derived fact has exactly one rule; the Derivation-Rule Registry Map owns it."
        "Remove the second claim rather than letting one rule silently win."
      ];

  # A registry entry must carry all four facts.
  ensureEntryComplete =
    site: entries:
    let
      incomplete = lib.filter (
        entry:
        !(
          isNonEmptyString (entry.ruleId or null)
          && isNonEmptyString (entry.derivedFact or null)
          && isNonEmptyString (entry.owningLayer or null)
          && builtins.isList (entry.determiningFacts or null)
          && (entry.determiningFacts or [ ]) != [ ]
        )
      ) entries;
    in
    require (incomplete == [ ])
      "E_DERIVATION_RULE_INCOMPLETE"
      [ "derivationRegistry" ]
      site
      "a registry entry omits its rule identity, determining declared facts, owning deriving layer, or derived fact"
      [ "Every rule names all four facts so the derivation is auditable rather than a silent default." ];

  # A rule may only produce what its determining declared facts determine. A rule
  # presented as licence to default-fill some other fact is refused.
  # A rule may only produce a derived fact the SDS map knows. A rule that names an
  # unmapped derived fact is claiming licence to default-fill a value no declared
  # fact determines.
  mappedFacts = map (entry: entry.derivedFact) defaultEntries;

  ensureNoDefaultFill =
    site: entries:
    let
      offenders = lib.filter (
        entry:
        !(builtins.isList (entry.determiningFacts or null))
        || (entry.determiningFacts or [ ]) == [ ]
        || !(builtins.elem (entry.derivedFact or null) mappedFacts)
      ) entries;
    in
    require (offenders == [ ])
      "E_DERIVATION_DEFAULT_FILL_REFUSED"
      [ "derivationRegistry" ]
      site
      "a rule claims an output its determining declared facts do not determine, so it would default-fill that fact"
      [ "A rule may not default-fill a fact it does not determine; declare the determining facts or drop the rule." ];
in
{
  inherit defaultEntries ruleIdentities;

  # Resolve a derived fact to exactly one registry entry. A fact with no entry is
  # an unsubstantiated derivation, named with the requesting layer — not a
  # locally synthesized value or a permissive default.
  resolve =
    {
      site ? null,
      entries ? defaultEntries,
      derivedFact,
      requestingLayer ? "network-compiler",
    }:
    let
      _valid = builtins.deepSeq (ensureNoDuplicateIdentities site entries) (
        builtins.deepSeq (ensureEntryComplete site entries) (builtins.deepSeq (ensureNoDefaultFill site entries) true)
      );
      matches = lib.filter (entry: entry.derivedFact == derivedFact) entries;
      found = builtins.head matches;
      _resolved =
        require (matches != [ ])
          "E_DERIVATION_UNSUBSTANTIATED"
          [
            "derivationRegistry"
            derivedFact
          ]
          site
          "unsubstantiated derivation: '${derivedFact}' requested by ${requestingLayer} has no entry in the Derivation-Rule Registry"
          [
            "Add the missing registry entry naming the determining facts, owning layer, and derived fact."
            "A derived value is never synthesized locally or default-filled."
          ];
    in
    builtins.seq _valid (builtins.seq _resolved {
      inherit (found)
        ruleId
        derivedFact
        determiningFacts
        owningLayer
        ;
    });

  # Classify a supplied field as `declared` or `derivable`. A field is derivable
  # exactly when a registry entry produces it; everything else is declared input.
  # This creates no authority: it only says where the value must come from.
  classify =
    {
      entries ? defaultEntries,
      field,
    }:
    let
      derivable = builtins.any (entry: entry.derivedFact == field) entries;
    in
    if derivable then "derivable" else "declared";

  # FS-172-HDS-010-SDS-010-SMS-030: the compiler input boundary (duplicate-writer
  # and rule/source-disagreement refusals) lives beside the registry but is a
  # distinct contract. Re-exported so callers depend on one module.
  inherit (import ./input-boundary.nix { inherit lib; })
    ensureNoDuplicateWriter
    ensureRuleSourceAgreement
    ;
}
