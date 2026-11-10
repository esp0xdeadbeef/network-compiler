{ lib }:

# FS-172-HDS-010-SDS-010-SMS-030: the compiler input boundary.
#
# A field classified `derivable` by the derivation-rule registry shall not be
# supplied as input: supplying it duplicates the writer that owns it. Where a rule
# and a hand-written source value disagree, the disagreement fails closed naming
# both values, and the source value is not an override.
#
# The fault is attributed to the owning deriving layer named in the registry, so
# it is raised by the layer that owns the derivation rather than anonymously by a
# classifier.

let
  util = import ../correctness/util.nix { inherit lib; };
  inherit (util) ensure;

  inherit (import ./data.nix) defaultEntries;

  require =
    cond: code: path: site: message: hints:
    ensure cond {
      inherit code;
      inherit path site message hints;
    };
in
{
  # Reject a derivable field supplied as input ("duplicate writer"), naming the
  # field, the scope, the determining facts, the owning rule, and the derived fact
  # it would overwrite.
  ensureNoDuplicateWriter =
    {
      site ? null,
      entries ? defaultEntries,
      suppliedFields,
      scope ? "site",
    }:
    let
      offenders = lib.filter (entry: builtins.elem entry.derivedFact suppliedFields) entries;
      offender = builtins.head offenders;
    in
    require (offenders == [ ])
      "E_DUPLICATE_WRITER"
      (map (entry: entry.derivedFact) offenders)
      site
      (
        if offenders == [ ] then
          "no duplicate writer"
        else
          "duplicate writer: field '${offender.derivedFact}' in scope '${scope}' is derivable by rule ${offender.ruleId} from determining declared facts ${builtins.concatStringsSep ", " offender.determiningFacts}; supplying it duplicates the derived fact's writer"
      )
      [
        "A field classified derivable shall not be supplied as input; remove it and let ${toString offender.ruleId} derive it."
      ];

  # A rule and a hand-written source value that disagree fail closed naming both;
  # the source value is not an override.
  ensureRuleSourceAgreement =
    {
      site ? null,
      field,
      ruleValue,
      sourceValue,
      ruleId ? "unknown-rule",
    }:
    require (ruleValue == sourceValue)
      "E_DERIVATION_RULE_SOURCE_DISAGREEMENT"
      [ field ]
      site
      "rule ${toString ruleId} and the supplied source value disagree on '${field}': rule says ${builtins.toJSON ruleValue}, source says ${builtins.toJSON sourceValue}; neither is an override"
      [
        "Restate one side so the rule and the source agree before the value is consumed."
      ];
}
