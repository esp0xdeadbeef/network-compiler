{ lib }:

let
  util = import ./util.nix { inherit lib; };
  inherit (util) ensure assertUnique throwError;

  normalizeLinkPair =
    pair:
    let
      a = builtins.elemAt pair 0;
      b = builtins.elemAt pair 1;
    in
    lib.sort builtins.lessThan [
      a
      b
    ];

  neighborsMap =
    nodeNames: links:
    let
      empty = lib.genAttrs nodeNames (_: [ ]);

      addEdge =
        acc: pair:
        let
          a = builtins.elemAt pair 0;
          b = builtins.elemAt pair 1;
        in
        acc
        // {
          "${a}" = (acc.${a} or [ ]) ++ [ b ];
          "${b}" = (acc.${b} or [ ]) ++ [ a ];
        };
    in
    builtins.foldl' addEdge empty links;

  bfs =
    neigh: start:
    let
      step =
        state: _:
        let
          queue = state.queue;
        in
        if queue == [ ] then
          state
        else
          let
            cur = builtins.head queue;
            rest = builtins.tail queue;

            ns = neigh.${cur} or [ ];
            unseen = lib.filter (n: !(builtins.elem n state.seen)) ns;

            seen' = state.seen ++ unseen;
            queue' = rest ++ unseen;
          in
          {
            seen = seen';
            queue = queue';
          };

      nodeCount = builtins.length (builtins.attrNames neigh);
      state0 = {
        seen = [ start ];
        queue = [ start ];
      };

      stateN = builtins.foldl' step state0 (lib.range 1 (nodeCount + 1));
    in
    stateN.seen;

  parseIpv4Cidr =
    siteKey: path: cidr:
    let
      parts = lib.splitString "/" cidr;

      _len = ensure (builtins.length parts == 2) {
        code = "E_UPLINK_INVALID_CIDR";
        site = siteKey;
        path = path;
        message = "invalid IPv4 CIDR '${toString cidr}'";
        hints = [ "Use a.b.c.d/prefix." ];
      };

      base = builtins.elemAt parts 0;
      prefix = lib.toInt (builtins.elemAt parts 1);

      octets = lib.splitString "." base;

      _octLen = ensure (builtins.length octets == 4) {
        code = "E_UPLINK_INVALID_IPV4";
        site = siteKey;
        path = path;
        message = "invalid IPv4 address '${base}'";
        hints = [ "Use four octets a.b.c.d." ];
      };

      toOctet =
        s:
        let
          v = lib.toInt s;
        in
        ensure (0 <= v && v <= 255) {
          code = "E_UPLINK_INVALID_IPV4";
          site = siteKey;
          path = path;
          message = "IPv4 octet out of range in '${base}'";
          hints = [ "Each octet must be 0..255." ];
        };

      _ = toOctet (builtins.elemAt octets 0);
      _1 = toOctet (builtins.elemAt octets 1);
      _2 = toOctet (builtins.elemAt octets 2);
      _3 = toOctet (builtins.elemAt octets 3);

      _pref = ensure (0 <= prefix && prefix <= 32) {
        code = "E_UPLINK_INVALID_PREFIX";
        site = siteKey;
        path = path;
        message = "invalid IPv4 prefix in '${cidr}'";
        hints = [ "Use /0..../32." ];
      };
    in
    true;

  parseIpv6Cidr =
    siteKey: path: cidr:
    let
      _parsed = lib.network.ipv6.fromString cidr;
    in
    true;

  validateOnePrefix =
    siteKey: path: cidr:
    if lib.hasInfix ":" cidr then parseIpv6Cidr siteKey path cidr else parseIpv4Cidr siteKey path cidr;

  validateIngressSubject =
    siteKey: path: ingressSubject:
    if ingressSubject == null then
      true
    else
      let
        _shape = ensure (builtins.isAttrs ingressSubject) {
          code = "E_UPLINK_INGRESS_SUBJECT_SHAPE";
          site = siteKey;
          path = path;
          message = "uplink.ingressSubject must be an attrset or null";
          hints = [ "Use ingressSubject = { kind = \"tenant\"; name = \"...\"; }." ];
        };

        kind = ingressSubject.kind or null;
        name = ingressSubject.name or null;

        _kind = ensure (kind != null) {
          code = "E_UPLINK_INGRESS_SUBJECT_KIND";
          site = siteKey;
          path = path ++ [ "kind" ];
          message = "uplink.ingressSubject.kind is required";
          hints = [ "Set kind = \"tenant\"." ];
        };

        _name = ensure (name != null && builtins.isString name && name != "") {
          code = "E_UPLINK_INGRESS_SUBJECT_NAME";
          site = siteKey;
          path = path ++ [ "name" ];
          message = "uplink.ingressSubject.name is required";
          hints = [ "Set name = \"...\"." ];
        };
      in
      true;

  validateUplinkPrefixes =
    siteKey: path: uplink:
    let
      ipv4 = uplink.ipv4 or [ ];
      ipv6 = uplink.ipv6 or [ ];
      ingressSubject = uplink.ingressSubject or null;

      _v4shape = ensure (builtins.isList ipv4 && builtins.all builtins.isString ipv4) {
        code = "E_UPLINK_PREFIX_SHAPE";
        site = siteKey;
        path = path ++ [ "ipv4" ];
        message = "uplink.ipv4 must be a list of CIDR strings";
        hints = [ "Use ipv4 = [ \"0.0.0.0/0\" \"203.0.113.0/24\" ]." ];
      };

      _v6shape = ensure (builtins.isList ipv6 && builtins.all builtins.isString ipv6) {
        code = "E_UPLINK_PREFIX_SHAPE";
        site = siteKey;
        path = path ++ [ "ipv6" ];
        message = "uplink.ipv6 must be a list of CIDR strings";
        hints = [ "Use ipv6 = [ \"::/0\" \"2001:db8::/32\" ]." ];
      };

      _nonEmpty = ensure (ipv4 != [ ] || ipv6 != [ ]) {
        code = "E_UPLINK_PREFIX_EMPTY";
        site = siteKey;
        path = path;
        message = "uplink must include at least one ipv4 and/or ipv6 prefix";
        hints = [ "Set ipv4 and/or ipv6 to a non-empty list of CIDR prefixes." ];
      };

      _v4ok = builtins.foldl' (acc: p: acc && validateOnePrefix siteKey (path ++ [ "ipv4" ]) p) true ipv4;
      _v6ok = builtins.foldl' (acc: p: acc && validateOnePrefix siteKey (path ++ [ "ipv6" ]) p) true ipv6;
      _ingressSubjectOk = validateIngressSubject siteKey (path ++ [ "ingressSubject" ]) ingressSubject;

      _forced = builtins.deepSeq {
        inherit
          _v4shape
          _v6shape
          _nonEmpty
          _v4ok
          _v6ok
          _ingressSubjectOk
          ;
      } true;
    in
    if _forced then true else true;

  normalizeUplinks =
    siteKey: nodeName: u:
    if u == null then
      [ ]
    else if builtins.isAttrs u then
      let
        names = lib.sort builtins.lessThan (builtins.attrNames u);

        _uniq = assertUnique "uplink name" names;

        uplinks = map (
          name:
          let
            v = u.${name};

            _shape = ensure (builtins.isAttrs v) {
              code = "E_UPLINK_ENTRY_SHAPE";
              site = siteKey;
              path = [
                "topology"
                "nodes"
                nodeName
                "uplinks"
                name
              ];
              message = "uplink '${name}' must be an attrset";
              hints = [ "Use uplinks.${name} = { ipv4 = [\"...\"]; ipv6 = [\"...\"]; }." ];
            };

            _valid = validateUplinkPrefixes siteKey [
              "topology"
              "nodes"
              nodeName
              "uplinks"
              name
            ] v;
          in
          v
          // {
            inherit name;
            ipv4 = v.ipv4 or [ ];
            ipv6 = v.ipv6 or [ ];
            ingressSubject = v.ingressSubject or null;
          }
        ) names;
      in
      if _uniq then uplinks else uplinks
    else
      [ ];

  logicalLinkName =
    pair:
    let
      ordered = normalizeLinkPair pair;
    in
    "${builtins.elemAt ordered 0}<->${builtins.elemAt ordered 1}";

  assertUniqueLogicalLinks =
    siteKey: links:
    let
      names = lib.sort builtins.lessThan (map logicalLinkName links);

      check =
        prev: rest:
        if rest == [ ] then
          true
        else
          let
            cur = builtins.head rest;
          in
          if prev == cur then
            throwError {
              code = "E_TOPO_DUPLICATE_LINK";
              site = siteKey;
              path = [
                "topology"
                "links"
              ];
              message = "duplicate logical link '${cur}'";
              hints = [ "Remove duplicate or reversed-duplicate topology.links entries." ];
            }
          else
            check cur (builtins.tail rest);
    in
    if names == [ ] then true else check (builtins.head names) (builtins.tail names);

  validateTopology =
    siteKey: topo:
    let
      nodes = topo.nodes or { };
      nodeNames = builtins.attrNames nodes;

      _uniqNodes = assertUnique "node name" nodeNames;

      roles = map (n: nodes.${n}.role or null) nodeNames;

      _hasCore = ensure (builtins.elem "core" roles) {
        code = "E_TOPO_MISSING_CORE";
        site = siteKey;
      };

      _hasPolicy = ensure (builtins.elem "policy" roles) {
        code = "E_TOPO_MISSING_POLICY";
        site = siteKey;
      };

      _hasAccess = ensure (builtins.elem "access" roles) {
        code = "E_TOPO_MISSING_ACCESS";
        site = siteKey;
      };

      links = topo.links or [ ];

      checkLink =
        pair:
        let
          _len = ensure (builtins.length pair == 2) {
            code = "E_TOPO_LINK_SHAPE";
            site = siteKey;
          };

          a = builtins.elemAt pair 0;
          b = builtins.elemAt pair 1;

          _a = ensure (builtins.elem a nodeNames) {
            code = "E_TOPO_UNKNOWN_NODE";
            site = siteKey;
          };

          _b = ensure (builtins.elem b nodeNames) {
            code = "E_TOPO_UNKNOWN_NODE";
            site = siteKey;
          };

          _notSelf = ensure (a != b) {
            code = "E_TOPO_SELF_LINK";
            site = siteKey;
            path = [
              "topology"
              "links"
            ];
            message = "topology link endpoints must be distinct";
            hints = [ "Replace self-links with links between two different nodes." ];
          };
        in
        true;

      _linksOk = builtins.foldl' (acc: pair: acc && (checkLink pair)) true links;
      normalizedLinks = map normalizeLinkPair links;
      _uniqLinks = assertUniqueLogicalLinks siteKey normalizedLinks;

      touched = lib.unique (
        lib.concatMap (pair: [
          (builtins.elemAt pair 0)
          (builtins.elemAt pair 1)
        ]) normalizedLinks
      );

      _noIsolated = builtins.foldl' (
        acc: n:
        acc
        && ensure (builtins.elem n touched) {
          code = "E_TOPO_DISCONNECTED";
          site = siteKey;
        }
      ) true nodeNames;

      neigh = neighborsMap nodeNames normalizedLinks;

      start = if nodeNames == [ ] then null else builtins.elemAt (lib.sort builtins.lessThan nodeNames) 0;

      seen = if start == null then [ ] else bfs neigh start;

      _connected = ensure (builtins.length seen == builtins.length nodeNames) {
        code = "E_TOPO_DISCONNECTED";
        site = siteKey;
      };

      coreNodes = lib.filter (n: (nodes.${n}.role or null) == "core") (
        lib.sort builtins.lessThan nodeNames
      );

      coreUplinks = lib.listToAttrs (
        map (n: {
          name = n;
          value =
            let
              us = normalizeUplinks siteKey n (nodes.${n}.uplinks or null);

              _required = ensure (builtins.length us > 0) {
                code = "E_CORE_UPLINKS_REQUIRED";
                site = siteKey;
                path = [
                  "topology"
                  "nodes"
                  n
                  "uplinks"
                ];
                message = "core node '${n}' must define at least one uplink";
                hints = [
                  "Set topology.nodes.${n}.uplinks = { wan = { ipv4 = [\"0.0.0.0/0\"]; ipv6 = [\"::/0\"]; }; }."
                ];
              };
            in
            if _required then us else us;
        }) coreNodes
      );

      uplinkCounts = map (n: builtins.length (coreUplinks.${n} or [ ])) coreNodes;

      totalUplinks = builtins.foldl' (
        acc: n: acc + (builtins.length (coreUplinks.${n} or [ ]))
      ) 0 coreNodes;

      anyMultiWan = totalUplinks > 1;

      _requiresUpstreamSelector = ensure (!anyMultiWan || builtins.elem "upstream-selector" roles) {
        code = "E_TOPO_MISSING_UPSTREAM_SELECTOR";
        site = siteKey;
        path = [
          "topology"
          "nodes"
        ];
        message = "multiple uplinks require an upstream-selector node";
        hints = [
          "Add a node with role = \"upstream-selector\"."
          "Connect it in topology.links between core and policy."
        ];
      };

      _force = builtins.deepSeq {
        inherit
          _uniqNodes
          _hasCore
          _hasPolicy
          _hasAccess
          _linksOk
          _uniqLinks
          _noIsolated
          _connected
          coreUplinks
          uplinkCounts
          totalUplinks
          _requiresUpstreamSelector
          ;
      } true;
    in
    builtins.seq _force true;
in
{
  inherit validateTopology;
}
