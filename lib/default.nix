{ lib }:
let
  mermaid = import ./mermaid.nix { inherit lib; };
  components = import ./components.nix { inherit lib mermaid; };
  sequence = import ./sequence.nix { inherit lib mermaid components; };
  architecture = import ./architecture.nix { inherit lib mermaid components; };
  markdown = import ./markdown.nix { inherit lib; };

  # ---------------------------------------------------------------------------
  # Validation across the whole model.
  # ---------------------------------------------------------------------------
  validateModel =
    model:
    let
      comps = model.components or { };
      seqsRaw = model.sequences or { };
      arch = model.architecture or { };
      seqs = map (id: {
        inherit id;
        seq = seqsRaw.${id};
      }) (builtins.attrNames seqsRaw);

      compErrs = components.validate comps;

      seqErrs = lib.concatLists (
        lib.mapAttrsToList (id: seq: sequence.validate { inherit comps id seq; }) seqsRaw
      );

      derivedKeys = architecture.edgeKeys seqs;

      edgeLabelErrs = lib.concatMap (
        k:
        lib.optional (!(lib.elem k derivedKeys))
          "architecture.edgeLabels has key `${k}` which no sequence message produces (expected one of: ${lib.concatStringsSep ", " derivedKeys})"
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
    compErrs ++ seqErrs ++ edgeLabelErrs ++ labelModeErrs ++ slugErrs;

  # ---------------------------------------------------------------------------
  # Rendering.
  # ---------------------------------------------------------------------------
  render =
    model:
    let
      comps = model.components or { };
      seqsRaw = model.sequences or { };
      arch = model.architecture or { };

      errors = validateModel model;
      throwErrors = throw ("architecture model is invalid:\n" + lib.concatStringsSep "\n" errors);

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
      seqTitle = s: s.seq.title or s.id;
      viewTitle = s: "${seqTitle s} — Components";

      renderSeq =
        s:
        markdown.page {
          title = seqTitle s;
          code = sequence.render {
            inherit comps;
            seq = s.seq;
          };
          related = [
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
            inherit comps;
            nodes = architecture.nodesForSequence { seq = s.seq; };
            seqs = [ s ];
            cfg = arch;
            title = viewTitle s;
          };
          related = [
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
          inherit comps seqs;
          nodes = architecture.globalNodes seqs;
          cfg = arch;
          title = archTitle;
        };
        related = map (s: {
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
    sequence
    architecture
    markdown
    ;
  inherit validateModel render renderDerivation;
}
