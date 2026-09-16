{
  lib,
  mermaid,
  components,
}:
let
  inherit (mermaid)
    escape
    quote
    shape
    classDefs
    styleColor
    ;
  inherit (components) flatten;

  # Recursively collect message steps (including inside blocks).
  walkMessages =
    step:
    if step ? message then
      [
        {
          from = step.message.from;
          to = step.message.to;
          label = step.message.label or "";
        }
      ]
    else if step ? loop then
      walkList (step.loop.steps or [ ])
    else if step ? opt then
      walkList (step.opt.steps or [ ])
    else if step ? break then
      walkList (step.break.steps or [ ])
    else if step ? rect then
      walkList (step.rect.steps or [ ])
    else if step ? alt then
      walkBranches step.alt
    else if step ? par then
      walkBranches step.par
    else if step ? parOver then
      walkBranches step.parOver
    else if step ? critical then
      walkBranches step.critical
    else
      [ ];

  walkList = xs: lib.concatMap walkMessages xs;

  walkBranches = b: lib.concatMap (br: walkList (br.steps or [ ])) (b.branches or [ ]);

  # Nodes referenced by non-message declarations (created actors) and messages.
  walkNodes =
    step:
    if step ? create then
      [ step.create ]
    else if step ? destroy then
      [ step.destroy ]
    else if step ? message then
      [
        step.message.from
        step.message.to
      ]
    else if step ? loop then
      walkNodeList (step.loop.steps or [ ])
    else if step ? opt then
      walkNodeList (step.opt.steps or [ ])
    else if step ? break then
      walkNodeList (step.break.steps or [ ])
    else if step ? rect then
      walkNodeList (step.rect.steps or [ ])
    else if step ? alt then
      walkNodeBranches step.alt
    else if step ? par then
      walkNodeBranches step.par
    else if step ? parOver then
      walkNodeBranches step.parOver
    else if step ? critical then
      walkNodeBranches step.critical
    else
      [ ];

  walkNodeList = xs: lib.concatMap walkNodes xs;

  walkNodeBranches = b: lib.concatMap (br: walkNodeList (br.steps or [ ])) (b.branches or [ ]);

  pushUnique = acc: x: if lib.elem x acc then acc else acc ++ [ x ];

  # Nodes for one sequence: declared participants first, then anything referenced.
  seqNodes =
    { seq, ... }:
    lib.foldl' pushUnique (seq.participants or [ ]) (walkNodes' (seq.steps or [ ]));

  walkNodes' = xs: lib.concatMap walkNodes xs;

  edgeKey = e: "${e.from}->${e.to}";

  # Aggregate messages across sequences into distinct edges.
  aggregate =
    seqs:
    let
      allMessages = lib.concatMap (s: walkList (s.seq.steps or [ ])) seqs;
      withoutSelf = lib.filter (m: m.from != m.to) allMessages;
    in
    lib.foldl' (
      acc: m:
      let
        k = edgeKey m;
      in
      acc
      // {
        ${k} = {
          from = m.from;
          to = m.to;
          count = (acc.${k}.count or 0) + 1;
          labels = (acc.${k}.labels or [ ]) ++ [ m.label ];
        };
      }
    ) { } withoutSelf;
in
rec {
  # Ordered unique nodes across all sequences.
  globalNodes = seqs: lib.foldl' pushUnique [ ] (lib.concatMap seqNodes seqs);

  nodesForSequence = seqNodes;

  edges = seqs: aggregate seqs;

  edgeKeys = seqs: builtins.attrNames (aggregate seqs);

  # ---------------------------------------------------------------------------
  # Graph rendering.
  # ---------------------------------------------------------------------------
  renderGraph =
    {
      comps,
      nodes,
      seqs,
      cfg,
      title,
    }:
    let
      direction = cfg.direction or "TD";
      labelMode = cfg.labelMode or "explicit";
      edgeLabels = cfg.edgeLabels or { };
      aggr = aggregate seqs;

      initLines = lib.optional (cfg ? config) "%%{init: ${builtins.toJSON cfg.config} }%%";

      nodeSet = nodes;
      flat = flatten comps;
      leafById =
        id:
        if flat.leaves ? ${id} then
          flat.leaves.${id}
        else
          throw "architecture references unknown component `${id}`";

      nodeLine = leaf: "${leaf.name}${shape leaf.kind (quote leaf.label)}";

      renderTree =
        nodeList:
        lib.concatMap (
          node:
          if node.type == "boundary" then
            let
              children = renderTree node.children;
            in
            if children == [ ] then
              [ ]
            else
              [ "subgraph ${node.id}[\"${escape node.label}\"]" ] ++ children ++ [ "end" ]
          else
            lib.optional (lib.elem node.name nodeSet) (nodeLine node)
        ) nodeList;

      renderEdge =
        e:
        let
          k = edgeKey e;
          label =
            if labelMode == "explicit" then
              edgeLabels.${k} or ""
            else if labelMode == "derived" then
              lib.concatStringsSep "<br/>" (lib.unique (map escape e.labels))
            else if labelMode == "count" then
              "${toString e.count} messages"
            else
              "";
        in
        "${e.from} -->${if label == "" then "" else "|\"${label}\"|"} ${e.to}";

      usedBoundaries = lib.filter (
        b: lib.any (n: lib.elem n nodeSet) (leafIdsIn comps b.path)
      ) (flatten comps).boundaries;

      styleLines = lib.filter (l: l != "") (
        map (
          b:
          if b.color == null then
            ""
          else
            let
              sc = styleColor b.color;
            in
            if sc == null then "" else "style ${b.id} fill:${sc},stroke:#4a5568,color:#1a202c"
        ) usedBoundaries
      );

      classLines = map (n: "class ${n} ${(leafById n).kind}") nodeSet;
    in
    mermaid.lines (
      initLines
      ++ [ "flowchart ${direction}" ]
      ++ renderTree (components.mkTree comps)
      ++ map renderEdge (lib.attrValues aggr)
      ++ classDefs
      ++ classLines
      ++ styleLines
    );

  # Leaf ids that live under a given boundary path.
  leafIdsIn =
    comps: path:
    let
      prefix = path;
    in
    map (l: l.name) (
      lib.filter (l: lib.take (lib.length prefix) l.path == prefix) (
        lib.attrValues (flatten comps).leaves
      )
    );
}
