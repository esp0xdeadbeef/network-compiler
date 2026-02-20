{ lib }:

site:

let
  alloc = import ./p2p/alloc.nix { inherit lib; };

  isBoxAttr =
    name: v:
    builtins.isAttrs v
    && !(lib.elem name [
      "role"
      "networks"
      "interfaces"
    ]);

  boxesOf = node: builtins.attrNames (lib.filterAttrs isBoxAttr node);

  roleOf = n: (n.role or null);

  expandPair =
    a: b:
    let
      na = site.nodes.${a};
      nb = site.nodes.${b};

      expandSide =
        nodeName: node:
        let
          boxes = boxesOf node;
        in
        if boxes == [ ] then [ nodeName ] else map (b: "${nodeName}.${b}") boxes;

      lefts = expandSide a na;
      rights = expandSide b nb;

    in
    lib.concatMap (
      l:
      map (r: [
        l
        r
      ]) rights
    ) lefts;

  expandedLinks = lib.concatMap (
    pair: expandPair (builtins.elemAt pair 0) (builtins.elemAt pair 1)
  ) site.links;

  allocSite = site // {
    links = expandedLinks;
  };

  links = alloc.alloc { site = allocSite; };

  emptyNode =
    n:
    let
      boxes = boxesOf n;
    in
    n
    // {
      interfaces = { };
    }
    // lib.genAttrs boxes (_: {
      interfaces = { };
    });

  nodes0 = lib.mapAttrs (_: emptyNode) site.nodes;

  splitName =
    name:
    let
      parts = lib.splitString "." name;
    in
    if builtins.length parts == 1 then
      {
        node = name;
        box = null;
      }
    else
      {
        node = builtins.elemAt parts 0;
        box = builtins.elemAt parts 1;
      };

  attach =
    nodesAcc: linkName: link:
    let
      epNames = builtins.attrNames link.endpoints;

      addOne =
        nodesA: ep:
        let
          parsed = splitName ep;
          node = parsed.node;
          box = parsed.box;
          peer = lib.head (lib.remove ep epNames);
          epData = link.endpoints.${ep};

          iface = {
            peer = peer;
            kind = link.kind;
            addr4 = epData.addr4 or null;
            addr6 = epData.addr6 or null;
          };

        in
        if box == null then
          nodesA
          // {
            ${node} = nodesA.${node} // {
              interfaces = nodesA.${node}.interfaces // {
                ${linkName} = iface;
              };
            };
          }
        else
          nodesA
          // {
            ${node} = nodesA.${node} // {
              ${box} = nodesA.${node}.${box} // {
                interfaces = nodesA.${node}.${box}.interfaces // {
                  ${linkName} = iface;
                };
              };
            };
          };

    in
    builtins.foldl' addOne nodesAcc epNames;

  nodesWithP2P = lib.foldlAttrs attach nodes0 links;

  addAccessLan = lib.mapAttrs (
    nodeName: node:
    if (node.role or null) != "access" then
      node
    else
      let
        boxes = boxesOf node;

        addOne =
          acc: boxName:
          let
            box = acc.${boxName} or { };
            ifs = box.interfaces or { };
          in
          acc
          // {
            ${boxName} = box // {
              interfaces = ifs // {
                "lan-${boxName}" = {
                  kind = "lan";
                  carrier = "lan";
                };
              };
            };
          };

      in
      builtins.foldl' addOne node boxes
  ) nodesWithP2P;

in
{
  nodes = addAccessLan;
  inherit links;
}
