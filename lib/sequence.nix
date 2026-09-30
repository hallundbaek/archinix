{
  lib,
  mermaid,
  components,
  typeUtils,
}:
let
  inherit (mermaid)
    escape
    arrowTokens
    arrowEnum
    boxColor
    ;
  inherit (components)
    flatten
    resolveId
    isRef
    refNodeId
    boundaryByPath
    ;

  strings = lib.strings;
  lines = mermaid.lines;

  getLeaf =
    comps: id:
    let
      flat = flatten comps;
    in
    if flat.leaves ? ${id} then
      flat.leaves.${id}
    else
      throw "sequence references unknown component `${id}`";

  # Participant metadata for a component, a semantic type, or an ancestor ref.
  getParticipant =
    comps: types: resolveRef: id:
    if isRef id then
      let
        h = resolveRef id;
      in
      {
        label = h.label;
        kind = h.kind or "participant";
        isType = false;
        isExternal = true;
        nodeId = refNodeId id;
        links = [ ];
      }
    else if types ? ${id} then
      {
        label = types.${id}.label;
        kind = types.${id}.kind or "participant";
        isType = true;
        isExternal = false;
        nodeId = id;
        links = [ ];
      }
    else
      let
        l = getLeaf comps id;
      in
      {
        label = l.label;
        kind = typeUtils.resolveKind types l;
        isType = false;
        isExternal = false;
        nodeId = id;
        links = l.links or [ ];
      };

  # Mermaid-safe actor id for a reference or plain id.
  actorId = id: if isRef id then refNodeId id else id;

  decl =
    kind: id: label:
    if kind == "actor" then
      "actor ${id} as ${escape label}"
    else if kind == "participant" then
      "participant ${id} as ${escape label}"
    else
      "participant ${id}@{ \"type\": \"${kind}\" } as ${escape label}";

  createDecl =
    kind: id: label:
    if kind == "actor" then
      "create actor ${id} as ${escape label}"
    else if kind == "participant" then
      "create participant ${id} as ${escape label}"
    else
      "create participant ${id}@{ \"type\": \"${kind}\" } as ${escape label}";

  boundaryAt =
    comps: path:
    if path == [ ] then null else (boundaryByPath comps).${lib.concatStringsSep "/" path} or null;

  participantBoundary =
    comps: id:
    let
      flat = flatten comps;
    in
    if flat.leaves ? ${id} then flat.leaves.${id}.boundaryPath else [ ];

  # All non-empty prefixes of a path, shortest first.
  prefixes = path: map (n: lib.take n path) (lib.range 1 (lib.length path));

  # Trie of boundary paths -> direct members and ordered children. `order` lists
  # "#self" and child names in first-appearance order.
  buildBoundaryTree =
    comps: ids:
    let
      empty = {
        members = [ ];
        children = { };
        order = [ ];
      };
      addOrder = order: tag: if lib.elem tag order then order else order ++ [ tag ];
      insert =
        node: path: id:
        if path == [ ] then
          node
          // {
            members = node.members ++ [ id ];
            order = addOrder node.order "#self";
          }
        else
          let
            name = lib.head path;
            rest = lib.tail path;
          in
          node
          // {
            children = node.children // {
              ${name} = insert (node.children.${name} or empty) rest id;
            };
            order = addOrder node.order name;
          };
    in
    lib.foldl' (acc: id: insert acc (participantBoundary comps id) id) empty ids;

  # Order participants so each nested boundary's members are adjacent, with the
  # outermost boundary's direct members first and subgroups following.
  orderedParticipants =
    comps: ids:
    let
      root = buildBoundaryTree comps ids;
      collect =
        node:
        lib.concatMap (
          tag: if tag == "#self" then node.members else collect node.children.${tag}
        ) node.order;
    in
    collect root;

  # Group participants by their outermost (top-level) boundary, in first
  # appearance order; participants without a boundary are unboxed.
  groupParticipants =
    comps: participants:
    let
      annotated = map (id: {
        inherit id;
        top =
          let
            bp = participantBoundary comps id;
          in
          if bp == [ ] then null else lib.head bp;
      }) participants;
      keys = lib.unique (map (a: a.top) annotated);
    in
    map (k: {
      top = k;
      members = map (a: a.id) (lib.filter (a: a.top == k) annotated);
    }) keys;

  defaultRects = [
    "rgba(0,0,0,0.04)"
    "rgba(0,0,0,0.08)"
    "rgba(0,0,0,0.12)"
    "rgba(0,0,0,0.16)"
  ];

  # A low-opacity tint of a boundary colour (keeps text readable), or null for
  # colours we cannot translate (named/hsl).
  tintColor =
    c:
    let
      sc = boxColor c;
      m = builtins.match "rgb\\(([0-9]+,[0-9]+,[0-9]+)\\)" sc;
    in
    if m != null then
      "rgba(${builtins.elemAt m 0},0.12)"
    else if builtins.match "rgba\\([^)]*\\)" sc != null then
      sc
    else
      null;

  rectColor =
    path: b:
    let
      tc = if b != null && b.color != null then tintColor b.color else null;
    in
    if tc != null then
      tc
    else
      lib.elemAt defaultRects (lib.min (lib.length path - 1) (lib.length defaultRects - 1));

  # A `box` around the participants of the outermost boundary (Mermaid boxes can
  # only contain participant declarations, so nesting is expressed separately).
  renderBoxGroup =
    comps: types: resolveRef: group:
    let
      meta = if group.top == null then null else boundaryAt comps [ group.top ];
      declOf =
        id:
        let
          p = getParticipant comps types resolveRef id;
        in
        decl p.kind p.nodeId p.label;
    in
    if meta == null then
      map declOf group.members
    else
      [
        (
          if meta.color != null then
            "box ${boxColor meta.color} ${escape meta.label}"
          else
            "box ${escape meta.label}"
        )
      ]
      ++ map declOf group.members
      ++ [ "end" ];

  # Rects + spanning notes for boundaries nested inside the outermost one,
  # emitted after the participant declarations; rects nest to mirror the
  # boundary hierarchy.
  renderInnerRects =
    comps: types: resolveRef: participants:
    let
      annotated = map (id: {
        inherit id;
        bp = participantBoundary comps id;
      }) participants;
      innerPaths = lib.unique (
        lib.concatMap (a: lib.filter (p: lib.length p >= 2) (prefixes a.bp)) annotated
      );
      membersOf = p: map (a: a.id) (lib.filter (a: lib.take (lib.length p) a.bp == p) annotated);
      childrenOf = p: lib.filter (q: lib.lists.init q == p) innerPaths;
      roots = lib.filter (p: lib.length p == 2) innerPaths;
      actorOf = id: (getParticipant comps types resolveRef id).nodeId;
      emit =
        p:
        let
          b = boundaryAt comps p;
          members = membersOf p;
          span =
            if lib.length members == 1 then
              [ (lib.head members) ]
            else
              [
                (lib.head members)
                (lib.last members)
              ];
          note = "Note over ${lib.concatStringsSep "," (map actorOf span)}: ${escape b.label}";
        in
        [ "rect ${rectColor p b}" ] ++ [ note ] ++ lib.concatMap emit (childrenOf p) ++ [ "end" ];
    in
    lib.concatMap emit roots;

  # Actors referenced by a step, in order of appearance (all step kinds).
  stepActors =
    step:
    if step ? message then
      [
        (resolveId step.message.from)
        (resolveId step.message.to)
      ]
    else if step ? note then
      map resolveId (step.note.actors or [ ])
    else if step ? activate then
      [ (resolveId step.activate) ]
    else if step ? deactivate then
      [ (resolveId step.deactivate) ]
    else if step ? create then
      [ (resolveId step.create) ]
    else if step ? destroy then
      [ (resolveId step.destroy) ]
    else if step ? properties then
      [ (resolveId step.properties.actor) ]
    else if step ? details then
      [ (resolveId step.details.actor) ]
    else if step ? loop then
      listActors (step.loop.steps or [ ])
    else if step ? opt then
      listActors (step.opt.steps or [ ])
    else if step ? break then
      listActors (step.break.steps or [ ])
    else if step ? rect then
      listActors (step.rect.steps or [ ])
    else if step ? alt then
      branchActors step.alt
    else if step ? par then
      branchActors step.par
    else if step ? parOver then
      branchActors step.parOver
    else if step ? critical then
      branchActors step.critical
    else
      [ ];

  listActors = lib.concatMap stepActors;
  branchActors = b: lib.concatMap (br: listActors (br.steps or [ ])) (b.branches or [ ]);

  # Participants created mid-sequence; they must not be pre-declared.
  stepCreated =
    step:
    if step ? create then
      [ (resolveId step.create) ]
    else if step ? loop then
      listCreated (step.loop.steps or [ ])
    else if step ? opt then
      listCreated (step.opt.steps or [ ])
    else if step ? break then
      listCreated (step.break.steps or [ ])
    else if step ? rect then
      listCreated (step.rect.steps or [ ])
    else if step ? alt then
      branchCreated step.alt
    else if step ? par then
      branchCreated step.par
    else if step ? parOver then
      branchCreated step.parOver
    else if step ? critical then
      branchCreated step.critical
    else
      [ ];

  listCreated = lib.concatMap stepCreated;
  branchCreated = b: lib.concatMap (br: listCreated (br.steps or [ ])) (b.branches or [ ]);

  # Participants inferred from the steps, minus those declared via `create`.
  inferParticipants =
    seq:
    let
      steps = seq.steps or [ ];
      created = listCreated steps;
    in
    lib.filter (id: !(lib.elem id created)) (lib.unique (listActors steps));

  # Explicit `participants` (order/boxing) extended with any actor referenced in
  # the steps but not listed, or, when omitted, fully inferred from the steps.
  effectiveParticipants =
    seq:
    if seq ? participants then
      let
        provided = map resolveId seq.participants;
        created = listCreated (seq.steps or [ ]);
        extra = lib.filter (id: !(lib.elem id provided) && !(lib.elem id created)) (inferParticipants seq);
      in
      provided ++ extra
    else
      inferParticipants seq;

  # Participants declared at the top of the diagram, ordered by boundary nesting.
  # Created participants that live inside a boundary are declared here too (so
  # they can be grouped and referenced by boundary notes); boundary-less created
  # participants keep using the `create` directive.
  declaredParticipants =
    comps: seq:
    let
      base = effectiveParticipants seq;
      created = listCreated (seq.steps or [ ]);
      inBoundary = lib.filter (t: participantBoundary comps t != [ ]) created;
      all = base ++ lib.filter (t: !(lib.elem t base)) inBoundary;
    in
    orderedParticipants comps all;
in
rec {
  render =
    {
      comps,
      seq,
      types,
      resolveRef,
    }:
    let
      participants = declaredParticipants comps seq;
      steps = seq.steps or [ ];

      initJson = lib.optional (seq ? config) "%%{init: ${builtins.toJSON seq.config} }%%";

      titleLines = lib.optional (seq ? diagramTitle) "title ${escape seq.diagramTitle}";

      # Accessibility metadata is derived from the sequence title/description.
      accessLines =
        lib.optional (seq ? title) "accTitle: ${escape seq.title}"
        ++ lib.optional (seq ? description) (
          if strings.match ".*\n.*" seq.description != null then
            "accDescr {\n${
              strings.removeSuffix "\n" (lib.replaceStrings [ "}" ] [ "#125;" ] seq.description)
            }\n}"
          else
            "accDescr: ${escape seq.description}"
        );

      autonumberLines =
        let
          a = seq.autonumber or false;
        in
        if a == false then
          [ ]
        else if a == true then
          [ "autonumber" ]
        else if a == "off" then
          [ "autonumber off" ]
        else if a ? start && a ? increment then
          [ "autonumber ${toString a.start} ${toString a.increment}" ]
        else if a ? start then
          [ "autonumber ${toString a.start}" ]
        else
          [ "autonumber" ];

      renderStep =
        step:
        if step ? comment then
          [ "%% ${step.comment}" ]
        else if step ? message then
          [ (renderMessage step.message) ]
        else if step ? note then
          [ (renderNote step.note) ]
        else if step ? activate then
          [ "activate ${actorId step.activate}" ]
        else if step ? deactivate then
          [ "deactivate ${actorId step.deactivate}" ]
        else if step ? create then
          # Created participants inside a boundary are declared up front.
          if lib.elem step.create participants then
            [ ]
          else
            (
              let
                l = getLeaf comps step.create;
              in
              [ (createDecl l.kind step.create l.label) ]
            )
        else if step ? destroy then
          [ "destroy ${step.destroy}" ]
        else if step ? loop then
          renderBlock "loop" step.loop
        else if step ? opt then
          renderBlock "opt" step.opt
        else if step ? break then
          renderBlock "break" step.break
        else if step ? rect then
          lib.concatLists [
            [ "rect ${step.rect.color}" ]
            (renderSteps step.rect.steps)
            [ "end" ]
          ]
        else if step ? alt then
          renderBranches "alt" "else" step.alt
        else if step ? par then
          renderBranches "par" "and" step.par
        else if step ? parOver then
          renderBranches "par_over" "and" step.parOver
        else if step ? critical then
          renderBranches "critical" "option" step.critical
        else if step ? properties then
          [ "properties ${step.properties.actor}: ${escape step.properties.text}" ]
        else if step ? details then
          [ "details ${step.details.actor}: ${escape step.details.text}" ]
        else
          throw "unknown sequence step: ${builtins.toJSON step}";

      renderSteps = lib.concatMap renderStep;

      renderBlock =
        kw: b: [ "${kw} ${escape (b.label or "")}" ] ++ renderSteps (b.steps or [ ]) ++ [ "end" ];

      renderBranches =
        kw: sep: b:
        let
          branches = if (b.branches or [ ]) == [ ] then [ { steps = [ ]; } ] else b.branches;
          firstLabel = b.label or ((lib.head branches).label or "");
          parts = lib.imap0 (
            i: br:
            (if i == 0 then [ "${kw} ${escape firstLabel}" ] else [ "${sep} ${escape (br.label or "")}" ])
            ++ renderSteps (br.steps or [ ])
          ) branches;
        in
        lib.concatLists parts ++ [ "end" ];

      renderMessage =
        m:
        let
          arrow =
            if m ? arrow && arrowTokens ? ${m.arrow} then arrowTokens.${m.arrow} else arrowTokens.solidArrow;
          central = m.central or "none";
          core =
            if central == "target" then
              arrow + "()"
            else if central == "source" then
              "()" + arrow
            else if central == "both" then
              "()" + arrow + "()"
            else
              arrow;
          shortcut =
            if m.activateTarget or false then
              "+"
            else if m.deactivateSource or false then
              "-"
            else
              "";
        in
        "${actorId m.from} ${core}${shortcut} ${actorId m.to}: ${escape (m.label or "")}";

      renderNote =
        n:
        let
          pos = n.position;
          actors = n.actors or [ ];
        in
        if pos == "over" && lib.length actors == 2 then
          "Note over ${actorId (lib.head actors)},${actorId (lib.elemAt actors 1)}: ${escape n.text}"
        else if pos == "over" then
          "Note over ${actorId (lib.head actors)}: ${escape n.text}"
        else if pos == "left" then
          "Note left of ${actorId (lib.head actors)}: ${escape n.text}"
        else if pos == "right" then
          "Note right of ${actorId (lib.head actors)}: ${escape n.text}"
        else
          throw "invalid note position `${toString pos}`";

      # `link` statements are not allowed inside a `box`, so emit them after.
      linkLines = lib.concatMap (
        id:
        let
          p = getParticipant comps types resolveRef id;
        in
        map (lk: "link ${p.nodeId}: ${escape lk.label} @ ${lk.url}") p.links
      ) participants;
    in
    lines (
      initJson
      ++ [ "sequenceDiagram" ]
      ++ titleLines
      ++ accessLines
      ++ autonumberLines
      ++ lib.concatMap (renderBoxGroup comps types resolveRef) (groupParticipants comps participants)
      ++ renderInnerRects comps types resolveRef participants
      ++ linkLines
      ++ renderSteps steps
    );

  # ---------------------------------------------------------------------------
  # Validation.
  # ---------------------------------------------------------------------------
  validate =
    {
      comps,
      id,
      seq,
      types,
      resolveRef,
    }:
    let
      flat = flatten comps;
      isLeaf = n: builtins.isString n && flat.leaves ? ${n};
      isType = n: builtins.isString n && types ? ${n};
      isExt = n: isRef n;
      memberIds = typeUtils.members comps types;
      hasMembers = t: lib.length (memberIds.${t} or [ ]) > 0;
      participants =
        if seq ? participants && !(builtins.isList seq.participants) then
          [ ]
        else
          declaredParticipants comps seq;

      hereAt =
        path:
        "sequence `${id}`" + lib.optionalString (path != [ ]) (" > " + lib.concatStringsSep " > " path);

      # An actor reference may name a component, a type, or an ancestor ref.
      refErrors =
        here: n:
        if isExt n then
          lib.optional (resolveRef n == null) "${here}: `${n}` does not resolve to an ancestor component"
        else if !(builtins.isString n) then
          [ "${here}: expected a component or type id" ]
        else if isLeaf n then
          [ ]
        else if isType n then
          lib.optional (!(hasMembers n)) "${here}: type `${n}` has no components"
        else
          [ "${here}: `${n}` is not a defined component or type" ];

      # Only concrete components can be created or destroyed.
      leafErrors =
        here: n:
        if isExt n then
          [ "${here}: `${n}` is an ancestor reference, not a concrete component" ]
        else if !(builtins.isString n) then
          [ "${here}: expected a component id" ]
        else if isLeaf n then
          lib.optional (flat.leaves.${n}.hasChild or false
          ) "${here}: `${n}` owns a sub-architecture and cannot be created/destroyed"
        else if isType n then
          [ "${here}: `${n}` is a type, not a concrete component" ]
        else
          [ "${here}: `${n}` is not a defined component" ];

      walk =
        path: step:
        let
          here = hereAt path;
          msg = step.message or { };
        in
        if step ? comment then
          [ ]
        else if step ? message then
          refErrors here (resolveId (msg.from or ""))
          ++ refErrors here (resolveId (msg.to or ""))
          ++
            lib.optional (msg ? arrow && !(lib.elem msg.arrow arrowEnum))
              "${here}: unknown arrow `${toString msg.arrow}`; expected one of: ${lib.concatStringsSep ", " arrowEnum}"
          ++
            lib.optional
              (
                !(lib.elem (msg.central or "none") [
                  "none"
                  "target"
                  "source"
                  "both"
                ])
              )
              "${here}: invalid central `${toString (msg.central or null)}`; expected none, target, source or both"
          ++ lib.optional (
            (msg.activateTarget or false) && (msg.deactivateSource or false)
          ) "${here}: message cannot set both activateTarget and deactivateSource"
          ++ lib.optional (
            ((msg.central or "none") != "none")
            && ((msg.activateTarget or false) || (msg.deactivateSource or false))
          ) "${here}: central connection cannot be combined with the +/- activation shortcut"
        else if step ? note then
          let
            pos = step.note.position;
            actors = map resolveId (step.note.actors or [ ]);
          in
          lib.optional (
            !(lib.elem pos [
              "over"
              "left"
              "right"
            ])
          ) "${here}: invalid note position `${toString pos}`"
          ++ lib.optional (
            !(lib.elem (lib.length actors) (
              if pos == "over" then
                [
                  1
                  2
                ]
              else
                [ 1 ]
            ))
          ) "${here}: note `${toString pos}` needs ${if pos == "over" then "one or two" else "one"} actor(s)"
          ++ lib.concatMap (n: refErrors here n) actors
        else if step ? activate then
          refErrors here (resolveId step.activate)
        else if step ? deactivate then
          refErrors here (resolveId step.deactivate)
        else if step ? create then
          leafErrors here (resolveId step.create)
        else if step ? destroy then
          leafErrors here (resolveId step.destroy)
        else if step ? loop then
          walkBlock path "loop" step.loop
        else if step ? opt then
          walkBlock path "opt" step.opt
        else if step ? break then
          walkBlock path "break" step.break
        else if step ? rect then
          lib.optional (
            !(step.rect ? color) || !(builtins.isString step.rect.color)
          ) "${here}: rect needs a string `color`"
          ++ lib.optional (
            step.rect ? color
            && builtins.isString step.rect.color
            && !(strings.match "(rgb|rgba)\\([^)]*\\)" step.rect.color != null)
          ) "${here}: rect color must use rgb()/rgba() syntax"
          ++ lib.concatMap (walk (path ++ [ "rect" ])) (step.rect.steps or [ ])
        else if step ? alt then
          walkBranches path "alt" 1 step.alt
        else if step ? par then
          walkBranches path "par" 1 step.par
        else if step ? parOver then
          walkBranches path "par_over" 1 step.parOver
        else if step ? critical then
          walkBranches path "critical" 0 step.critical
        else if step ? properties then
          refErrors here (resolveId step.properties.actor)
          ++ lib.optional (
            !(step.properties ? text) || !(builtins.isString step.properties.text)
          ) "${here}: properties needs a string `text`"
        else if step ? details then
          refErrors here (resolveId step.details.actor)
          ++ lib.optional (
            !(step.details ? text) || !(builtins.isString step.details.text)
          ) "${here}: details needs a string `text`"
        else
          [ "${here}: unknown step ${builtins.toJSON step}" ];

      walkBlock =
        path: name: b:
        lib.concatMap (walk (path ++ [ name ])) (b.steps or [ ]);

      walkBranches =
        path: name: minBranches: b:
        let
          branches = b.branches or [ ];
        in
        lib.optional (
          lib.length branches < minBranches
        ) "${hereAt (path ++ [ name ])}: `${name}` needs at least ${toString minBranches} branch(es)"
        ++ lib.concatLists (
          lib.imap0 (
            i: br: lib.concatMap (walk (path ++ [ "${name}[${toString i}]" ])) (br.steps or [ ])
          ) branches
        );

      stepErrors = lib.concatMap (walk [ ]) (seq.steps or [ ]);
    in
    (lib.optional (
      seq ? participants && !(builtins.isList seq.participants)
    ) "sequence `${id}`: `participants` must be a list if present")
    ++ lib.concatMap (n: refErrors "sequence `${id}`" n) participants
    ++ lib.optional (
      seq ? config && !(builtins.isAttrs seq.config)
    ) "sequence `${id}`: `config` must be an attribute set"
    ++ lib.optional (
      seq ? description && !(builtins.isString seq.description)
    ) "sequence `${id}`: `description` must be a string"
    ++ stepErrors;
}
// {
  inherit inferParticipants effectiveParticipants;
}
