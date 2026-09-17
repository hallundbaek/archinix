{ lib }:
let
  mermaid = import ./mermaid.nix { inherit lib; };
  components = import ./components.nix { inherit lib mermaid; };
  typeUtils = import ./types.nix { inherit lib mermaid components; };
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
  dsl = import ./dsl.nix { inherit lib mermaid components; };

  # ---------------------------------------------------------------------------
  # Validation across the whole model.
  # ---------------------------------------------------------------------------
  validateModel =
    model:
    let
      comps = model.components or { };
      types = model.types or { };
      seqsRaw = model.sequences or { };
      arch = model.architecture or { };

      typeMembers = typeUtils.members comps types;
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
              ;
          }
        ) seqsRaw
      );

      derivedKeys = architecture.edgeKeys seqs types typeMembers;
      originKeys = architecture.originKeys seqs;
      validLabelKeys = derivedKeys ++ originKeys;

      edgeLabelErrs = lib.concatMap (
        k:
        lib.optional (!(lib.elem k validLabelKeys))
          "architecture.edgeLabels has key `${k}` which no sequence message produces (expected one of: ${lib.concatStringsSep ", " validLabelKeys})"
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
      comps = model.components or { };
      types = model.types or { };
      seqsRaw = model.sequences or { };
      arch = model.architecture or { };

      errors = validateModel model;
      throwErrors = throw ("architecture model is invalid:\n" + lib.concatStringsSep "\n" errors);

      typeMembers = typeUtils.members comps types;

      seqOrder = arch.sequenceOrder or (builtins.attrNames seqsRaw);
      seqs = map (id: {
        inherit id;
        seq = seqsRaw.${id};
      }) seqOrder;

      seqFile = id: "${markdown.slug id}.md";
      viewFile = id: "${markdown.slug id}-architecture.md";
      archFile = "architecture.md";
      indexFile = "README.md";

      archTitle = arch.title or "System Architecture";
      overviewLabel = "Overview";
      seqTitle = s: s.seq.title or s.id;
      viewTitle = s: "${seqTitle s} — Components";

      renderSeq =
        s:
        markdown.page {
          title = seqTitle s;
          description = s.seq.description or null;
          code = sequence.render {
            inherit comps types;
            seq = s.seq;
          };
          related = [
            {
              label = overviewLabel;
              href = indexFile;
            }
            {
              label = archTitle;
              href = archFile;
            }
            {
              label = viewTitle s;
              href = viewFile s.id;
            }
          ];
        };

      renderView =
        s:
        markdown.page {
          title = viewTitle s;
          code = architecture.renderGraph {
            inherit comps types typeMembers;
            nodes = architecture.nodesForSequence {
              seq = s.seq;
              inherit types typeMembers;
            };
            seqs = [ s ];
            cfg = arch;
            title = viewTitle s;
          };
          related = [
            {
              label = overviewLabel;
              href = indexFile;
            }
            {
              label = seqTitle s;
              href = seqFile s.id;
            }
            {
              label = archTitle;
              href = archFile;
            }
          ];
        };

      archPage = markdown.page {
        title = archTitle;
        code = architecture.renderGraph {
          inherit
            comps
            types
            typeMembers
            seqs
            ;
          nodes = architecture.globalNodes { inherit seqs types typeMembers; };
          cfg = arch;
          title = archTitle;
        };
        related = [
          {
            label = overviewLabel;
            href = indexFile;
          }
        ]
        ++ map (s: {
          label = seqTitle s;
          href = seqFile s.id;
        }) seqs;
      };

      indexPage = markdown.index {
        title = model.title or "Architecture";
        intro = model.description or null;
        sections = [
          {
            title = "Architecture";
            pages = [
              {
                label = archTitle;
                href = archFile;
              }
            ]
            ++ map (s: {
              label = viewTitle s;
              href = viewFile s.id;
            }) seqs;
          }
          {
            title = "Sequences";
            pages = map (s: {
              label = seqTitle s;
              href = seqFile s.id;
            }) seqs;
          }
        ];
      };

      files = {
        ${indexFile} = indexPage;
        ${archFile} = archPage;
      }
      // lib.listToAttrs (map (s: lib.nameValuePair (seqFile s.id) (renderSeq s)) seqs)
      // lib.listToAttrs (map (s: lib.nameValuePair (viewFile s.id) (renderView s)) seqs);
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
    in
    pkgs.linkFarm name (
      lib.mapAttrsToList (n: content: {
        name = n;
        path = pkgs.writeText n content;
      }) files
    );
in
{
  inherit
    mermaid
    components
    typeUtils
    sequence
    architecture
    markdown
    dsl
    ;
  inherit validateModel render renderDerivation;
}
