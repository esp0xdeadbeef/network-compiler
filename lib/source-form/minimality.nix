{ lib }:

# FS-165-HDS-010-SDS-010: source-form minimality and readability, applied to the
# shape of the intent source itself.
#
# The compiler cannot tell a hand-written relation from one a helper produced
# after evaluation: both arrive as the same attrset. So this check reads the
# source *text*, where the difference is visible. A helper is written once and
# invoked; a repetitive source repeats the same lines per scope.
#
# The rule is about repetition, not size. A large intent that is dry stays
# readable because each fact is written once, and it passes. A short intent that
# repeats a block per scope fails, because repetition is what costs the reader. A
# derived field restated on every record is repetition too, which is why FS-180's
# closed-world defaults belong in the derivation, not in the source.
#
# Line shape is compared after masking identifier runs to '#', so renaming a
# tenant does not hide a repeated block: that is what makes this a repetition
# check rather than a textual diff.

let
  util = import ../correctness/util.nix { inherit lib; };
  inherit (util) ensure;

  # Mask every alphanumeric run. `allow-clients-to-tang` and
  # `allow-iot-srv-to-tang` become the same shape, so a repeated block is
  # detectable under any renaming.
  maskRuns =
    line:
    builtins.concatStringsSep "" (
      map (part: if builtins.isList part then "#" else part) (builtins.split "[A-Za-z0-9_]+" line)
    );

  # Drop a trailing comment so prose is not counted as structure. A '#' inside a
  # string is treated as a comment start; the cost is a missed detection, never a
  # false one, because the remainder of the line is discarded either way.
  stripComment =
    line:
    let
      parts = builtins.split "#" line;
    in
    if builtins.length parts <= 1 then line else builtins.head parts;

  meaningfulLines =
    text:
    builtins.filter (line: line != "") (
      map maskRuns (
        builtins.filter (line: line != "") (
          map (line: lib.trim (stripComment line)) (lib.splitString "\n" text)
        )
      )
    );

  # The comment-stripped, trimmed lines before masking. Structural detection runs
  # on these, because masking turns every identifier into '#' and '#' is itself
  # punctuation: a masked line of identifiers would otherwise look like a line of
  # braces and be discarded.
  cleanLines =
    text:
    builtins.filter (line: line != "") (
      map (line: lib.trim (stripComment line)) (lib.splitString "\n" text)
    );

  countBy =
    items:
    lib.foldl' (acc: item: acc // { ${item} = (acc.${item} or 0) + 1; }) { } items;

  topCount =
    counts:
    lib.foldl' (best: entry: if entry.value > best.value then entry else best) {
      name = null;
      value = 0;
    } (lib.mapAttrsToList (name: value: { inherit name value; }) counts);

  windows =
    size: items:
    if builtins.length items < size then
      [ ]
    else
      lib.genList (i: builtins.concatStringsSep "\n" (lib.sublist (i + 1) size items)) (
        builtins.length items - size + 1
      );

  # A line of pure punctuation ('{', '};', ']') repeats in any file and says
  # nothing about readability, so it is not counted as a repeated shape.
  isStructuralOnly = line: builtins.match "[\n [:punct:]]*" line != null;

  # A repeated *record* is a brace-bearing block rewritten per scope. A repeated
  # data row is a table: `tenant0 = "10.0.0.0/24";` written once per tenant is the
  # dry form this check exists to reward, so a window with no brace in it is not
  # counted as a repeated block.
  hasBrace = line: builtins.match ".*[{}].*" line != null;

  require =
    cond: code: path: site: message: hints:
    ensure cond {
      inherit code;
      inherit path site message hints;
    };

  # Report the repeated shapes without deciding. The caller decides whether the
  # source is repetitive enough to refuse.
  #
  # Size is deliberately not a failure on its own. The measure is the ratio of
  # distinct line shapes to lines written: a large intent that declares each fact
  # once keeps that ratio high, while a source that rewrites a block per scope
  # drives it down as it grows. A small file is exempt because repetition in a
  # 200-line file is ordinary Nix, not an unreadable source.
  analyze =
    {
      text,
      windowSize ? 2,
      maxRepetitionRatio ? 0.05,
      minLines ? 150,
    }:
    let
      raw = cleanLines text;
      masked = map maskRuns raw;
      indices = lib.range 0 (builtins.length raw - 1);
      candidateLines = map (i: builtins.elemAt masked i) (
        builtins.filter (i: !isStructuralOnly (builtins.elemAt raw i)) indices
      );
      lineCounts = countBy candidateLines;
      # The measure runs on brace-bearing structure only. A data table is one row
      # per fact with no brace in it, so it contributes nothing to the repetition
      # measure and can never be refused for being long.
      structuralLines = builtins.filter hasBrace candidateLines;
      allWindows = windows windowSize masked;
      # Retain only windows that still show a brace: those are rewritten records,
      # not repeated table rows.
      blockWindows = builtins.filter (
        window: builtins.any hasBrace (lib.splitString "\n" window)
      ) allWindows;
      windowCounts = countBy blockWindows;
      lineTotal = builtins.length structuralLines;
      distinctLines = builtins.length (
        builtins.attrNames (countBy structuralLines)
      );
      repetitionRatio =
        if lineTotal == 0 then 1.0 else (distinctLines * 1.0) / lineTotal;
      isLarge = lineTotal > minLines;
      tooRepetitive = repetitionRatio < maxRepetitionRatio;
    in
    {
      inherit
        masked
        lineCounts
        windowCounts
        lineTotal
        distinctLines
        repetitionRatio
        maxRepetitionRatio
        minLines
        isLarge
        tooRepetitive
        windowSize
        ;
      worstLine = topCount lineCounts;
      worstWindow = topCount windowCounts;
      ok = !(isLarge && tooRepetitive);
    };
in
{
  inherit maskRuns cleanLines meaningfulLines analyze;

  # Fail closed on a source that grows by rewriting the same block per scope. A
  # large intent passes whenever it declares each fact once; size alone is never
  # the reason for refusal.
  assertMinimal =
    {
      text,
      path ? [ "intent" ],
      site ? null,
      windowSize ? 2,
      maxRepetitionRatio ? 0.05,
      minLines ? 150,
    }:
    let
      result = analyze {
        inherit
          text
          windowSize
          maxRepetitionRatio
          minLines
          ;
      };
      pct = value: builtins.toString (builtins.floor (value * 10000.0)) + "bp";
    in
    require result.ok "E_SOURCE_FORM_REPETITION" path site (
      if result.ok then
        "source shape is within budget"
      else
        "source writes ${toString result.lineTotal} lines in only ${toString result.distinctLines} distinct shapes (${pct result.repetitionRatio}, budget ${pct maxRepetitionRatio}); the worst shape '${result.worstWindow.name}' recurs ${toString result.worstWindow.value} times, so the source grows by rewriting one block per scope instead of declaring each fact once"
    ) [
      "Write the repeated shape once as a helper or a data row and invoke it per scope, so each fact appears in the source once."
      "Do not drop the fact to satisfy the budget: every permission still has to be declared (FS-180, FS-181)."
      "Size is not the defect. A large intent that declares each fact once passes this check."
    ];
}
