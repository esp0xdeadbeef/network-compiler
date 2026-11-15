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

  # FS-172 DRV-SERVICE-PERMISSION-SHAPE: a relation's traffic class is derived from
  # the declaration of the service it targets. A relation that restates that class
  # duplicates the writer the registry names, so the restatement is refused rather
  # than accepted as an independent statement of the same meaning.
  #
  # The diagnostic carries the five elements FS-172-HDS-010-SDS-010-SMS-030
  # requires: field, declaring scope, determining declared fact, rule identity, and
  # derived value.
  ensurePermissionShapeNotRestated =
    {
      site ? null,
      relations ? [ ],
      serviceTrafficType ? { },
      entries ? defaultEntries,
    }:
    let
      rule = lib.findFirst (entry: entry.ruleId == "DRV-SERVICE-PERMISSION-SHAPE") null entries;

      targetServiceOf =
        relation:
        let
          to = relation.to or { };
        in
        if (to.kind or null) == "service" then to.name or null else null;

      restingOn =
        relation:
        let
          service = targetServiceOf relation;
          supplied = relation.trafficType or null;
          declared = if service == null then null else serviceTrafficType.${service} or null;
        in
        service != null && supplied != null && declared == supplied;

      offenders = lib.filter restingOn relations;
      offender = builtins.head offenders;
      offenderService = targetServiceOf offender;
      offenderScope = offender.id or offender.name or null;
      offenderSupplied = offender.trafficType or null;
      offenderDeclared = serviceTrafficType.${offenderService} or null;
      ruleId = if rule == null then "DRV-SERVICE-PERMISSION-SHAPE" else rule.ruleId;
    in
    require (offenders == [ ])
      "E_DUPLICATE_WRITER"
      [
        "relations"
        offenderScope
        "trafficType"
      ]
      site
      (
        if offenders == [ ] then
          "no permission-shape restatement"
        else
          "duplicate writer: relation '${toString offenderScope}' in scope '${toString site}' supplies trafficType ${builtins.toJSON offenderSupplied}, which rule ${ruleId} already derives from the declared service '${offenderService}' (serviceDeclaration.trafficType ${builtins.toJSON offenderDeclared}); supplying it restates the derived permissionShape"
      )
      [
        "Drop trafficType from the relation and let ${ruleId} derive the permission shape from the target service declaration."
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
