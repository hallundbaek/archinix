{
  lib,
  mermaid,
  components,
  sequence,
  typeUtils,
}:
let
  inherit (mermaid)
    escape
    quote
    shape
    classDefs
    styleColor
    styleText
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

  isType = types: id: lib.isString id && types ? ${id};

  # Expand a reference to the concrete component ids it denotes.
  instances =
    types: typeMembers: id:
    if isType types id then typeMembers.${id} or [ ] else [ id ];

  expandIds =
    types: typeMembers: ids:
    lib.concatMap (instances types typeMembers) ids;

  # Nodes for one sequence: participants and message endpoints, with types
  # expanded to their instances.
  seqNodes =
    {
      seq,
      types,
      typeMembers,
    }:
    lib.unique (
      expandIds types typeMembers (
        sequence.effectiveParticipants seq ++ lib.concatMap walkNodes (seq.steps or [ ])
      )
    );

  edgeKey = e: "${e.from}->${e.to}";
  originKey = o: "${o.from}->${o.to}";

  # Messages with each type endpoint expanded to its concrete instances.
  expandMessages =
    types: typeMembers: messages:
    lib.concatMap (
      m:
      let
        froms = instances types typeMembers m.from;
        tos = instances types typeMembers m.to;
      in
      lib.concatMap (
        f:
        lib.concatMap (
          t:
          lib.optional (f != t) {
            from = f;
            to = t;
            label = m.label;
            origin = {
              from = m.from;
              to = m.to;
            };
          }
        ) tos
      ) froms
    ) messages;

  # Aggregate messages across sequences into distinct edges.
  aggregate =
    seqs: types: typeMembers:
    let
      allMessages = lib.concatMap (s: walkList (s.seq.steps or [ ])) seqs;
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
          origins = lib.unique ((acc.${k}.origins or [ ]) ++ [ (originKey m.origin) ]);
        };
      }
    ) { } (expandMessages types typeMembers allMessages);

  messagesOf = seqs: lib.concatMap (s: walkList (s.seq.steps or [ ])) seqs;
in
rec {
  # Ordered unique nodes across all sequences.
  globalNodes =
    {
      seqs,
      types,
      typeMembers,
    }:
    lib.foldl' pushUnique [ ] (lib.concatMap (seqNodesOf types typeMembers) seqs);

  nodesForSequence = seqNodes;

  seqNodesOf =
    types: typeMembers: s:
    seqNodes {
      inherit (s) seq;
      inherit types typeMembers;
    };

  edges =
    seqs: types: typeMembers:
    aggregate seqs types typeMembers;

  # Concrete "from->to" keys a message produces.
  edgeKeys =
    seqs: types: typeMembers:
    builtins.attrNames (aggregate seqs types typeMembers);

  # Un-expanded "from->to" keys (component or type pairs) used by messages; these
  # are also valid `edgeLabels` keys and apply to every expansion.
  originKeys = seqs: lib.unique (map (m: "${m.from}->${m.to}") (messagesOf seqs));

  # ---------------------------------------------------------------------------
  # Graph rendering.
  # ---------------------------------------------------------------------------
  renderGraph =
    {
      comps,
      nodes,
      seqs,
      cfg,
      types,
      typeMembers,
      title,
    }:
    let
      direction = cfg.direction or "TD";
      labelMode = cfg.labelMode or "explicit";
      edgeLabels = cfg.edgeLabels or { };
      aggr = aggregate seqs types typeMembers;

      initLines = lib.optional (cfg ? config) "%%{init: ${builtins.toJSON cfg.config} }%%";

      nodeSet = nodes;
      flat = flatten comps;
      leafById =
        id:
        if flat.leaves ? ${id} then
          flat.leaves.${id}
        else
          throw "architecture references unknown component `${id}`";

      kindOf = id: typeUtils.resolveKind types (leafById id);

      nodeLine = leaf: "${leaf.name}${shape (kindOf leaf.name) (quote leaf.label)}";

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

      explicitLabel =
        e:
        edgeLabels.${edgeKey e}
        or (lib.foldl' (acc: o: if acc != "" then acc else edgeLabels.${o} or "") "" e.origins);

      renderEdge =
        e:
        let
          label =
            if labelMode == "explicit" then
              explicitLabel e
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

      boundaryStyleLines = lib.filter (l: l != "") (
        map (
          b:
          if b.color == null then
            ""
          else
            let
              sc = styleColor b.color;
            in
            if sc == null then "" else "style ${b.id} fill:${sc},stroke:#4a5568,color:${styleText b.color}"
        ) usedBoundaries
      );

      coloredLeaves = lib.filter (
        n: lib.elem n nodeSet && (typeUtils.resolveColor types (leafById n)) != null
      ) (builtins.attrNames flat.leaves);

      leafStyleLines = map (
        n:
        let
          c = typeUtils.resolveColor types (leafById n);
          sc = styleColor c;
        in
        "style ${n} fill:${sc},stroke:#4a5568,color:${styleText c}"
      ) coloredLeaves;

      classLines = map (n: "class ${n} ${kindOf n}") nodeSet;
    in
    mermaid.lines (
      initLines
      ++ [ "flowchart ${direction}" ]
      ++ renderTree (components.mkTree comps)
      ++ map renderEdge (lib.attrValues aggr)
      ++ classDefs
      ++ classLines
      ++ leafStyleLines
      ++ boundaryStyleLines
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
