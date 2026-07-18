{
  lib,
  localRaw,
  helpers,
}:

let
  warnings =
    if localRaw == null then
      [ ]
    else
      let
        requester = localRaw.requester or { };
        lateral = localRaw.lateralPolicy or { };
        leaks =
          (requester.recursion or false)
          || (requester.publicFallback or false)
          || (lateral.transitiveEgress or false);
      in
      lib.optional leaks (helpers.warning {
        code = "DNS_LOCAL_ONLY_AUTHORITY_LEAK";
        requester = "service:${toString (requester.service or "<missing>")}";
        resolverService = toString ((localRaw.authority or { }).service or "<missing>");
        candidateIds = [ (toString ((localRaw.relation or { }).id or "<missing>")) ];
        context = "local-only-authority";
      });
in
{
  inherit warnings;
  normalized = if localRaw == null || warnings != [ ] then null else localRaw;
}
