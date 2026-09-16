{
  lib,
  mermaid,
  components,
}:
let
  inherit (mermaid)
    escape
    arrowTokens
    arrowEnum
    boxColor
    ;
  inherit (components) flatten;

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

  groupParticipants =
    comps: participants:
    let
      flat = flatten comps;
      annotated = map (id: {
        inherit id;
        top = flat.leaves.${id}.topBoundary;
      }) participants;
      keys = lib.unique (map (a: a.top) annotated);
    in
    map (k: {
      top = k;
      members = map (a: a.id) (lib.filter (a: a.top == k) annotated);
    }) keys;

  boundaryMeta =
    comps: key:
    let
      bs = lib.filter (b: lib.length b.path == 1 && b.name == key) (flatten comps).boundaries;
    in
    if bs == [ ] then null else lib.head bs;
in
rec {
  render =
    { comps, seq }:
    let
      participants = seq.participants or [ ];
      steps = seq.steps or [ ];

      initJson = lib.optional (seq ? config) "%%{init: ${builtins.toJSON seq.config} }%%";

      titleLines = lib.optional (seq ? diagramTitle) "title ${escape seq.diagramTitle}";

      accessLines =
        (lib.optional (
          seq ? accessibility && seq.accessibility ? title
        ) "accTitle: ${escape seq.accessibility.title}")
        ++ (lib.optional (seq ? accessibility && seq.accessibility ? description) (
          if strings.match ".*\n.*" seq.accessibility.description != null then
            "accDescr {\n${strings.removeSuffix "\n" seq.accessibility.description}\n}"
          else
            "accDescr: ${escape seq.accessibility.description}"
        ));

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
          [ "activate ${step.activate}" ]
        else if step ? deactivate then
          [ "deactivate ${step.deactivate}" ]
        else if step ? create then
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
        "${m.from} ${core}${shortcut} ${m.to}: ${escape (m.label or "")}";

      renderNote =
        n:
        let
          pos = n.position;
          actors = n.actors or [ ];
        in
        if pos == "over" && lib.length actors == 2 then
          "Note over ${lib.head actors},${lib.elemAt actors 1}: ${escape n.text}"
        else if pos == "over" then
          "Note over ${lib.head actors}: ${escape n.text}"
        else if pos == "left" then
          "Note left of ${lib.head actors}: ${escape n.text}"
        else if pos == "right" then
          "Note right of ${lib.head actors}: ${escape n.text}"
        else
          throw "invalid note position `${toString pos}`";

      renderParticipantGroup =
        group:
        let
          meta = if group.top == null then null else boundaryMeta comps group.top;
          decls = map (
            id:
            let
              l = getLeaf comps id;
            in
            decl l.kind id l.label
          ) group.members;
        in
        if meta == null then
          decls
        else
          [
            (
              if meta.color != null then
                "box ${boxColor meta.color} ${escape meta.label}"
              else
                "box ${escape meta.label}"
            )
          ]
          ++ decls
          ++ [ "end" ];

      # `link` statements are not allowed inside a `box`, so emit them after.
      linkLines = lib.concatMap (
        id:
        let
          l = getLeaf comps id;
        in
        map (lk: "link ${id}: ${escape lk.label} @ ${lk.url}") (l.links or [ ])
      ) participants;
    in
    lines (
      initJson
      ++ [ "sequenceDiagram" ]
      ++ titleLines
      ++ accessLines
      ++ autonumberLines
      ++ lib.concatMap renderParticipantGroup (groupParticipants comps participants)
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
    }:
    let
      flat = flatten comps;
      hasLeaf = n: builtins.isString n && flat.leaves ? ${n};
      participants = seq.participants or [ ];

      hereAt =
        path:
        "sequence `${id}`" + lib.optionalString (path != [ ]) (" > " + lib.concatStringsSep " > " path);
      missing = here: n: "${here}: component `${toString n}` is not defined in `components`";

      walk =
        path: step:
        let
          here = hereAt path;
          msg = step.message or { };
        in
        if step ? comment then
          [ ]
        else if step ? message then
          lib.optional (!(hasLeaf msg.from)) "${missing here msg.from} (message.from)"
          ++ lib.optional (!(hasLeaf msg.to)) "${missing here msg.to} (message.to)"
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
            actors = step.note.actors or [ ];
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
          ++ lib.concatMap (n: lib.optional (!(hasLeaf n)) "${missing here n} (note actor)") actors
        else if step ? activate then
          lib.optional (!(hasLeaf step.activate)) "${missing here step.activate} (activate)"
        else if step ? deactivate then
          lib.optional (!(hasLeaf step.deactivate)) "${missing here step.deactivate} (deactivate)"
        else if step ? create then
          lib.optional (!(hasLeaf step.create)) "${missing here step.create} (create)"
          ++ lib.optional (lib.elem step.create participants) "${here}: created component `${step.create}` must not also be listed in participants"
        else if step ? destroy then
          lib.optional (!(hasLeaf step.destroy)) "${missing here step.destroy} (destroy)"
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
          lib.optional (!(hasLeaf step.properties.actor)) "${missing here step.properties.actor} (properties)"
          ++ lib.optional (
            !(step.properties ? text) || !(builtins.isString step.properties.text)
          ) "${here}: properties needs a string `text`"
        else if step ? details then
          lib.optional (!(hasLeaf step.details.actor)) "${missing here step.details.actor} (details)"
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
      !(seq ? participants) || !(builtins.isList participants)
    ) "sequence `${id}`: `participants` must be a list")
    ++ lib.concatMap (
      n:
      lib.optional (
        !(hasLeaf n)
      ) "sequence `${id}`: participant `${toString n}` is not defined in `components`"
    ) participants
    ++ lib.optional (
      seq ? config && !(builtins.isAttrs seq.config)
    ) "sequence `${id}`: `config` must be an attribute set"
    ++ stepErrors;
}
