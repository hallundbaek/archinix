{
  lib,
  mermaid,
  components,
  typeUtils,
  dsl,
}:
let
  inherit (components)
    flatten
    isRef
    refDepth
    refName
    ;

  # -- reference resolution against an ancestor context chain ---------------
  # ctx exposes the ancestor level's component handles directly (`parent.db`),
  # plus `types` and `parent` (the next ancestor up).
  lookupRef =
    ctx: ref:
    if !(isRef ref) then
      null
    else
      let
        n = refDepth ref;
        id = refName ref;
        walk =
          c: k:
          if c == null then
            null
          else if k == 1 then
            c
          else
            walk c.parent (k - 1);
        c = walk ctx n;
      in
      if c == null then null else c.${id} or null;

  # -- ancestor context construction ----------------------------------------
  componentHandles =
    comps: types: up:
    lib.mapAttrs (name: leaf: {
      id = name;
      inherit up;
      label = leaf.label;
      kind = typeUtils.resolveKind types leaf;
      color = typeUtils.resolveColor types leaf;
      componentTypes = leaf.componentTypes;
    }) (flatten comps).leaves;

  typeHandles =
    types: up:
    lib.mapAttrs (name: spec: {
      id = name;
      inherit up;
      label = spec.label;
      kind = spec.kind or null;
      color = spec.color or null;
    }) types;

  # This level's own handles (up = 0).
  levelCtx =
    comps: types:
    componentHandles comps types 0
    // {
      types = typeHandles types 0;
      parent = null;
    };

  bump =
    h:
    h
    // {
      up = (h.up or 0) + 1;
    };

  bumpContext =
    ctx:
    lib.mapAttrs (n: h: if n == "types" || n == "parent" then h else bump h) (
      lib.filterAttrs (n: _: n != "types" && n != "parent") ctx
    )
    // {
      types = lib.mapAttrs (n: bump) ctx.types;
      parent = if ctx.parent == null then null else bumpContext ctx.parent;
    };

  # Context exposed to a child: this level's handles become `up = 1`, with the
  # level's own ancestors shifted one further up.
  childContext =
    own: parentCtx:
    lib.mapAttrs (n: bump) (lib.filterAttrs (n: _: n != "types") own)
    // {
      types = lib.mapAttrs (n: bump) own.types;
      parent = if parentCtx == null then null else bumpContext parentCtx;
    };

  resolveChild =
    childArg: ctx:
    if lib.isFunction childArg then
      childArg {
        archinix = dsl;
        parent = ctx;
      }
    else if lib.isPath childArg || lib.isString childArg then
      import childArg {
        archinix = dsl;
        parent = ctx;
      }
    else
      childArg;

  # -- message walking ------------------------------------------------------
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

  seqMessages =
    lv:
    lib.concatMap (sid: walkList (lv.model.sequences.${sid}.steps or [ ])) (
      builtins.attrNames (lv.model.sequences or { })
    );
in
rec {
  # Load the (root) model and all nested models into a tree.
  load =
    {
      path ? [ ],
      model,
      parentCtx ? null,
      seen ? [ ],
    }:
    let
      comps = model.components or { };
      types = model.types or { };
      typeMembers = typeUtils.members comps types;
      own = levelCtx comps types;
      childCtx = childContext own parentCtx;
      flat = flatten comps;
      composites = map (n: flat.leaves.${n}) (lib.filter (n: flat.leaves.${n}.hasChild) flat.leafOrder);
      children = map (
        leaf:
        let
          key = toString leaf.child;
        in
        if lib.elem key seen then
          throw "archinix: circular sub-architecture at `${key}`"
        else
          load {
            path = path ++ [ leaf.name ];
            model = resolveChild leaf.child childCtx;
            parentCtx = childCtx;
            seen = seen ++ [ key ];
          }
      ) composites;
    in
    {
      inherit
        path
        model
        comps
        types
        typeMembers
        parentCtx
        children
        ;
      depth = lib.length path;
    };

  flattenLevels = root: [ root ] ++ lib.concatMap flattenLevels root.children;

  levelsByDepth = levels: lib.listToAttrs (map (lv: lib.nameValuePair (toString lv.depth) lv) levels);

  # -- cross-boundary edge lifting -----------------------------------------
  # For every message with an ancestor endpoint, produce the (mirrored) edges
  # and external nodes for each level it crosses, keyed by absolute depth.
  crossEdges =
    levels:
    let
      byDepth = levelsByDepth levels;

      leafAt = lv: id: (flatten lv.comps).leaves.${id} or { label = id; };

      stepLevel =
        acc: lv:
        let
          d = lv.depth;
          path = lv.path;
        in
        lib.foldl' (
          acc2: m:
          let
            refs = lib.filter isRef [
              m.from
              m.to
            ];
          in
          if refs == [ ] then
            acc2
          else
            let
              targetLevels = map (r: d - refDepth r) refs;
              kStart = lib.foldl' (a: b: if a > b then a else b) 0 targetLevels;
              ks = lib.genList (i: kStart + i) (d - kStart + 1);
            in
            lib.foldl' (
              acc3: k:
              let
                nodesFor =
                  e:
                  if isRef e then
                    let
                      l = d - refDepth e;
                      id = refName e;
                    in
                    if k == l then [ id ] else [ "anc_${toString (k - l)}_${id}" ]
                  else if k == d then
                    (if lv.types ? ${e} then lv.typeMembers.${e} or [ ] else [ e ])
                  else
                    [ (lib.elemAt path k) ];

                froms = nodesFor m.from;
                tos = nodesFor m.to;
                edges = lib.concatMap (
                  f:
                  lib.concatMap (
                    t:
                    lib.optional (f != t) {
                      from = f;
                      to = t;
                      label = m.label;
                    }
                  ) tos
                ) froms;
                extNodes =
                  lib.concatMap
                    (
                      e:
                      if !(isRef e) then
                        [ ]
                      else
                        let
                          l = d - refDepth e;
                          id = refName e;
                          lvL = byDepth.${toString l};
                        in
                        lib.optional (k > l) {
                          id = "anc_${toString (k - l)}_${id}";
                          label = (leafAt lvL id).label;
                          kind = typeUtils.resolveKind lvL.types (leafAt lvL id);
                        }
                    )
                    [
                      m.from
                      m.to
                    ];
                key = toString k;
                prev =
                  acc3.${key} or {
                    nodes = { };
                    edges = [ ];
                  };
              in
              acc3
              // {
                ${key} = {
                  nodes = prev.nodes // lib.listToAttrs (map (n: lib.nameValuePair n.id n) extNodes);
                  edges = prev.edges ++ edges;
                };
              }
            ) acc2 ks
        ) acc (seqMessages lv);

      final = lib.foldl' stepLevel { } levels;
    in
    lib.mapAttrs (_: v: {
      nodes = lib.attrValues v.nodes;
      edges = v.edges;
    }) final;
}
// {
  inherit lookupRef;
}
