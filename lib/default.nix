{ lib }:
let
  mermaid = import ./mermaid.nix { inherit lib; };
  components = import ./components.nix { inherit lib mermaid; };
  typeUtils = import ./types.nix { inherit lib mermaid components; };
  dsl = import ./dsl.nix { inherit lib mermaid components; };
  nesting = import ./nesting.nix {
    inherit
      lib
      mermaid
      components
      typeUtils
      dsl
      ;
  };
  sequence = import ./sequence.nix {
    inherit
      lib
      mermaid
      components
      typeUtils
      ;
  };
  architecture = import ./architecture.nix {
    inherit
      lib
      mermaid
      components
      sequence
      typeUtils
      ;
  };
  markdown = import ./markdown.nix { inherit lib; };

  seqList =
    lv:
    let
      raw = lv.model.sequences or { };
      order = (lv.model.architecture or { }).sequenceOrder or (builtins.attrNames raw);
    in
    map (id: {
      inherit id;
      seq = raw.${id};
    }) order;

  compositesOf =
    lv:
    let
      flat = components.flatten lv.comps;
    in
    map (n: flat.leaves.${n}) (lib.filter (n: flat.leaves.${n}.hasChild) flat.leafOrder);

  dirOf = lv: lib.concatStringsSep "/" lv.path;
  prefixOf = lv: if lv.path == [ ] then "" else dirOf lv + "/";

  seqPath = lv: id: prefixOf lv + markdown.slug id + ".md";
  viewPath = lv: id: prefixOf lv + markdown.slug id + "-architecture.md";
  archPath = lv: prefixOf lv + "architecture.md";
  parentArchPath = lv: lib.concatStringsSep "/" (lib.lists.init lv.path) + "/architecture.md";

  archTitle = lv: (lv.model.architecture or { }).title or (lv.model.title or "System Architecture");
  seqTitle = s: s.seq.title or s.id;
  viewTitle = s: "${seqTitle s} — Components";

  levelLabel =
    lv:
    if lv.path == [ ] then (lv.model.title or "Architecture") else lib.concatStringsSep " / " lv.path;

  crossOf =
    cross: lv:
    cross.${toString lv.depth} or {
      nodes = [ ];
      edges = [ ];
    };

  # ---------------------------------------------------------------------------
  # Validation (per level).
  # ---------------------------------------------------------------------------
  validateLevel =
    {
      lv,
      extraKeys ? [ ],
    }:
    let
      model = lv.model;
      comps = lv.comps;
      types = lv.types;
      typeMembers = lv.typeMembers;
      arch = model.architecture or { };
      seqsRaw = model.sequences or { };
      resolveRef = nesting.lookupRef lv.parentCtx;
      seqs = map (id: {
        inherit id;
        seq = seqsRaw.${id};
      }) (builtins.attrNames seqsRaw);

      compErrs = components.validate comps;
      typeRegErrs = typeUtils.validateRegistry types;
      typeUseErrs = typeUtils.validateUsage { inherit types comps; };

      seqErrs = lib.concatLists (
        lib.mapAttrsToList (
          id: seq:
          sequence.validate {
            inherit
              comps
              types
              id
              seq
              resolveRef
              ;
          }
        ) seqsRaw
      );

      derivedKeys = architecture.edgeKeys seqs types typeMembers;
      originKeys = architecture.originKeys seqs;
      validLabelKeys = derivedKeys ++ originKeys ++ extraKeys;

      edgeLabelErrs = lib.concatMap (
        k:
        lib.optional (!(lib.elem k validLabelKeys))
          "architecture.edgeLabels has key `${k}` which no message produces (expected one of: ${lib.concatStringsSep ", " validLabelKeys})"
      ) (builtins.attrNames (arch.edgeLabels or { }));

      labelMode = arch.labelMode or "explicit";
      labelModeErrs = lib.optional (
        !(lib.elem labelMode [
          "explicit"
          "derived"
          "count"
          "none"
        ])
      ) "architecture.labelMode must be one of: explicit, derived, count, none";

      slugs = map (id: markdown.slug id) (builtins.attrNames seqsRaw);
      slugDupes = lib.unique (lib.filter (s: lib.length (lib.filter (x: x == s) slugs) > 1) slugs);
      slugErrs = lib.optional (
        slugDupes != [ ]
      ) "sequence ids produce duplicate slugs: ${lib.concatStringsSep ", " slugDupes}";
    in
    compErrs ++ typeRegErrs ++ typeUseErrs ++ seqErrs ++ edgeLabelErrs ++ labelModeErrs ++ slugErrs;

  # ---------------------------------------------------------------------------
  # Rendering.
  # ---------------------------------------------------------------------------
  render =
    model:
    let
      root = nesting.load { inherit model; };
      levels = nesting.flattenLevels root;
      cross = nesting.crossEdges levels;

      errors = lib.concatLists (
        lib.map (
          lv:
          validateLevel {
            inherit lv;
            extraKeys = map (e: "${e.from}->${e.to}") (crossOf cross lv).edges;
          }
        ) levels
      );
      throwErrors = throw ("architecture model is invalid:\n" + lib.concatStringsSep "\n" errors);

      # External nodes/edges relevant to a set of local nodes.
      externalFor =
        lv: localNodes:
        let
          c = crossOf cross lv;
          usedExternal = map (n: n.id) c.nodes;
          edges = lib.filter (
            e:
            (lib.elem e.from localNodes && lib.elem e.to usedExternal)
            || (lib.elem e.to localNodes && lib.elem e.from usedExternal)
            || (lib.elem e.from usedExternal && lib.elem e.to usedExternal)
          ) c.edges;
          nodeIds = lib.unique (
            lib.concatMap (e: [
              e.from
              e.to
            ]) edges
          );
          nodes = lib.filter (n: lib.elem n.id nodeIds) c.nodes;
        in
        {
          externalNodes = nodes;
          extraEdges = edges;
        };

      renderGraphFor =
        lv:
        let
          flat = components.flatten lv.comps;
          crossLocal = lib.filter (n: flat.leaves ? ${n}) (
            lib.concatMap (e: [ e.from e.to ]) (crossOf cross lv).edges
          );
          nodes = lib.unique (
            architecture.globalNodes {
              seqs = seqList lv;
              inherit (lv) types typeMembers;
            }
            ++ crossLocal
          );
        in
        architecture.renderGraph {
          comps = lv.comps;
          inherit (lv) types typeMembers;
          inherit nodes;
          seqs = seqList lv;
          cfg = lv.model.architecture or { };
          externalNodes = (crossOf cross lv).nodes;
          extraEdges = (crossOf cross lv).edges;
          title = archTitle lv;
        };

      levelFiles =
        lv:
        let
          dir = dirOf lv;
          rel = markdown.relPath dir;
          resolveRef = nesting.lookupRef lv.parentCtx;
          archPage = markdown.page {
            title = archTitle lv;
            code = renderGraphFor lv;
            related = [
              {
                label = "Overview";
                href = rel "README.md";
              }
            ]
            ++ lib.optional (lv.path != [ ]) {
              label = "Up";
              href = rel (parentArchPath lv);
            }
            ++ map (s: {
              label = seqTitle s;
              href = rel (seqPath lv s.id);
            }) (seqList lv)
            ++ map (leaf: {
              label = "Sub-architecture: ${leaf.label}";
              href = rel (prefixOf lv + leaf.name + "/architecture.md");
            }) (compositesOf lv);
          };

          renderSeq =
            s:
            markdown.page {
              title = seqTitle s;
              description = s.seq.description or null;
              code = sequence.render {
                comps = lv.comps;
                types = lv.types;
                seq = s.seq;
                inherit resolveRef;
              };
              related = [
                {
                  label = "Overview";
                  href = rel "README.md";
                }
                {
                  label = archTitle lv;
                  href = rel (archPath lv);
                }
                {
                  label = viewTitle s;
                  href = rel (viewPath lv s.id);
                }
              ];
            };

          renderView =
            s:
            let
              localNodes = architecture.nodesForSequence {
                seq = s.seq;
                inherit (lv) types typeMembers;
              };
              ext = externalFor lv localNodes;
            in
            markdown.page {
              title = viewTitle s;
              code = architecture.renderGraph {
                comps = lv.comps;
                inherit (lv) types typeMembers;
                nodes = localNodes;
                seqs = [ s ];
                cfg = lv.model.architecture or { };
                externalNodes = ext.externalNodes;
                extraEdges = ext.extraEdges;
                title = viewTitle s;
              };
              related = [
                {
                  label = "Overview";
                  href = rel "README.md";
                }
                {
                  label = seqTitle s;
                  href = rel (seqPath lv s.id);
                }
                {
                  label = archTitle lv;
                  href = rel (archPath lv);
                }
              ];
            };

          seqs = seqList lv;
        in
        {
          ${archPath lv} = archPage;
        }
        // lib.listToAttrs (map (s: lib.nameValuePair (seqPath lv s.id) (renderSeq s)) seqs)
        // lib.listToAttrs (map (s: lib.nameValuePair (viewPath lv s.id) (renderView s)) seqs);

      indexPage = markdown.index {
        title = root.model.title or "Architecture";
        intro = root.model.description or null;
        sections = [
          {
            title = "Architectures";
            pages = map (lv: {
              label = levelLabel lv;
              href = markdown.relPath "" (archPath lv);
            }) levels;
          }
          {
            title = "Sequences";
            pages = lib.concatMap (
              lv:
              map (s: {
                label = (if lv.path == [ ] then "" else levelLabel lv + ": ") + seqTitle s;
                href = markdown.relPath "" (seqPath lv s.id);
              }) (seqList lv)
            ) levels;
          }
        ];
      };

      files = {
        "README.md" = indexPage;
      }
      // lib.listToAttrs (
        lib.concatMap (lv: lib.mapAttrsToList (n: v: lib.nameValuePair n v) (levelFiles lv)) levels
      );
    in
    if errors != [ ] then throwErrors else files;

  # A directory derivation containing every generated markdown file.
  renderDerivation =
    {
      pkgs,
      model,
      name ? "architecture-docs",
    }:
    let
      files = render model;
      writes = lib.mapAttrsToList (
        path: content:
        "mkdir -p \"$out/${builtins.dirOf path}\"\n"
        + "cat > \"$out/${path}\" <<'ARCHINIX_EOF'\n"
        + content
        + "\nARCHINIX_EOF\n"
      ) files;
    in
    pkgs.runCommand name { } ("mkdir -p $out\n" + lib.concatStringsSep "\n" writes);

  # Backwards-compatible: validate the root model and its descendants.
  validateModel =
    model:
    let
      root = nesting.load { inherit model; };
      levels = nesting.flattenLevels root;
      cross = nesting.crossEdges levels;
    in
    lib.concatLists (
      lib.map (
        lv:
        validateLevel {
          inherit lv;
          extraKeys = map (e: "${e.from}->${e.to}") (crossOf cross lv).edges;
        }
      ) levels
    );
in
let
  self = {
    inherit
      mermaid
      components
      typeUtils
      nesting
      sequence
      architecture
      markdown
      dsl
      ;
    inherit validateModel render renderDerivation;
    mkOutputs = (import ./mkOutputs.nix { lib = self; }).mkOutputs;
  };
in
self
