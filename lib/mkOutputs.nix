{ lib }:
let
  serverPath = ./preview/server.py;

  defaultSystems = [
    "x86_64-linux"
    "aarch64-linux"
    "aarch64-darwin"
  ];

  # Where `render` writes and `watch` serves. Defaults to `docsPath`'s directory
  # name, so `docsPath = ./generated;` also redirects generation there.
  outDirOf =
    {
      docsDir ? null,
      docsPath ? null,
    }:
    if docsDir != null then
      docsDir
    else if docsPath != null then
      baseNameOf (toString docsPath)
    else
      "docs";

  # git-hooks.nix-compatible hook running the docs check when model/ or the docs
  # dir change.
  mkDocsHook =
    { docsDir }:
    {
      docs-up-to-date = {
        enable = true;
        name = "docs-up-to-date";
        entry = "nix run .#render -- ${docsDir} --check";
        files = "^(model|${docsDir})/";
        pass_filenames = false;
        language = "system";
      };
    };

  renderApp =
    pkgs: src: dest:
    pkgs.writeShellApplication {
      name = "render-architecture-docs";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.diffutils
      ];
      text = ''
        set -euo pipefail
        dest="''${1:-${dest}}"
        mode="''${2:-}"
        src="${src}"

        if [ "$mode" = "--check" ]; then
          if ! diff -ru "$src" "$dest"; then
            echo "error: generated docs are out of date; run 'nix run .#render'" >&2
            exit 1
          fi
          echo "docs are up to date"
        else
          rm -rf "$dest"
          mkdir -p "$dest"
          cp -rL "$src"/. "$dest"/
          chmod -R u+w "$dest"
          echo "wrote docs to $dest"
        fi
      '';
    };

  mermaidCliApp =
    pkgs: docsDir:
    if pkgs ? "mermaid-cli" then
      {
        check-mermaid = {
          type = "app";
          program = "${
            pkgs.writeShellApplication {
              name = "check-mermaid";
              runtimeInputs = [
                pkgs.coreutils
                pkgs.gawk
                pkgs.mermaid-cli
              ];
              text = ''
                set -euo pipefail
                src="${docsDir}"
                out="$(mktemp -d)"
                status=0
                find "$src" -name '*.md' -print0 | while IFS= read -r -d "" f; do
                  base="$(basename "$f" .md)"
                  awk '/^```mermaid$/{flag=1;next} /^```$/{flag=0} flag' "$f" > "$out/$base.mmd"
                  if [ ! -s "$out/$base.mmd" ]; then
                    continue
                  fi
                  if err="$(mmdc -q -i "$out/$base.mmd" -o "$out/$base.svg" 2>&1)"; then
                    echo "ok: $base"
                  elif printf '%s' "$err" | grep -q "reading 'class'"; then
                    echo "skip (mermaid-cli actor-menu popup bug): $base"
                  else
                    printf '%s\n' "$err" >&2
                    echo "FAIL: $base" >&2
                    status=1
                  fi
                done
                exit "$status"
              '';
            }
          }/bin/check-mermaid";
          meta.description = "Render every diagram with mermaid-cli to validate it";
        };
      }
    else
      { };

  watchApp =
    pkgs: dest:
    let
      mermaidJs =
        if pkgs ? "mermaid-cli" then
          "${pkgs.mermaid-cli}/lib/node_modules/@mermaid-js/mermaid-cli/node_modules/mermaid/dist/mermaid.min.js"
        else
          "";
      open =
        if pkgs.stdenv.hostPlatform.isDarwin then "/usr/bin/open" else "${pkgs.xdg-utils}/bin/xdg-open";
      python = pkgs.python3.withPackages (ps: [ ps.markdown ]);
    in
    pkgs.writeShellApplication {
      name = "archinix-watch";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.findutils
        pkgs.watchexec
        pkgs.nix
        python
      ];
      text = ''
        export ARCHINIX_SERVER="${serverPath}"
        export ARCHINIX_MERMAID_JS="${mermaidJs}"
        export ARCHINIX_OPEN="${open}"

        root="''${ARCHINIX_ROOT:-$PWD}"
        port="''${PORT:-8080}"
        do_open=1

        usage() {
          echo "usage: archinix-watch [--root DIR] [--port N] [--no-open]" >&2
        }

        while [ $# -gt 0 ]; do
          case "$1" in
            --root) root="$2"; shift 2 ;;
            --port) port="$2"; shift 2 ;;
            --no-open) do_open=0; shift ;;
            -h|--help) usage; exit 0 ;;
            *) usage; exit 2 ;;
          esac
        done

        if [ ! -d "$root/model" ]; then
          echo "error: no model/ directory in $root" >&2
          echo "run this from an Archinix project, or pass --root DIR" >&2
          exit 1
        fi

        docs="$root/${dest}"
        nix_args=(--extra-experimental-features nix-command --extra-experimental-features flakes)

        echo "[archinix] initial render"
        nix "''${nix_args[@]}" run "$root#render" -- "$docs"

        python3 "$ARCHINIX_SERVER" --root "$docs" --port "$port" --host 127.0.0.1 &
        server_pid=$!
        cleanup() { kill "$server_pid" 2>/dev/null || true; }
        trap cleanup EXIT INT TERM

        url="http://127.0.0.1:$port/"
        echo "[archinix] serving $url (Ctrl-C to stop)"
        if [ "$do_open" = 1 ]; then
          ( sleep 1; "$ARCHINIX_OPEN" "$url" >/dev/null 2>&1 || true ) &
        fi

        watch_paths=()
        for d in model lib; do
          if [ -d "$root/$d" ]; then
            watch_paths+=(--watch "$root/$d")
          fi
        done

        watchexec \
          "''${watch_paths[@]}" \
          --exts nix \
          --debounce 250ms \
          --postpone \
          -- nix "''${nix_args[@]}" run "$root#render" -- "$docs"
      '';
    };

  # Per-system outputs, shared by `mkOutputs` and the flake-parts module.
  mkSystemOutputs =
    {
      pkgs,
      model,
      docsPath ? null,
      docsDir ? null,
      markdownFormatter ? null,
      name ? "architecture-docs",
    }:
    let
      outDir = outDirOf { inherit docsDir docsPath; };
      rawDocs = lib.renderDerivation { inherit pkgs model name; };
      docs =
        if markdownFormatter == null then
          rawDocs
        else
          markdownFormatter {
            inherit pkgs;
            src = rawDocs;
          };
      checks =
        if docsPath == null then
          { }
        else
          {
            docs-up-to-date =
              pkgs.runCommand "docs-up-to-date"
                {
                  nativeBuildInputs = [ pkgs.diffutils ];
                  generated = docs;
                  committed = docsPath;
                }
                ''
                  if ! diff -ru "$generated" "$committed"; then
                    echo "error: committed docs/ differ from generated output" >&2
                    exit 1
                  fi
                  touch $out
                '';
          };
      apps = mermaidCliApp pkgs docs // {
        render = {
          type = "app";
          program = "${renderApp pkgs docs outDir}/bin/render-architecture-docs";
          meta.description = "Regenerate the Markdown docs from the model";
        };
        watch = {
          type = "app";
          program = "${watchApp pkgs outDir}/bin/archinix-watch";
          meta.description = "Watch the model and serve a live HTML preview";
        };
        preview = {
          type = "app";
          program = "${watchApp pkgs outDir}/bin/archinix-watch";
          meta.description = "Watch the model and serve a live HTML preview";
        };
        default = {
          type = "app";
          program = "${renderApp pkgs docs outDir}/bin/render-architecture-docs";
          meta.description = "Regenerate the Markdown docs from the model";
        };
      };
    in
    {
      inherit outDir;
      packages = {
        docs = docs;
        default = docs;
      };
      inherit apps checks;
    };

  mkOutputs =
    {
      nixpkgs,
      model,
      docsPath ? null,
      docsDir ? null,
      markdownFormatter ? null,
      name ? "architecture-docs",
      systems ? defaultSystems,
      extraChecks ? (_: { }),
      devShellPackages ? (_: [ ]),
      gitHooks ? { },
    }:
    let
      outDir = outDirOf { inherit docsDir docsPath; };
      forAll = f: nixpkgs.lib.genAttrs systems (system: f (import nixpkgs { inherit system; }));
      sysOf =
        pkgs:
        mkSystemOutputs {
          inherit
            pkgs
            model
            docsPath
            docsDir
            markdownFormatter
            name
            ;
        };

      gitHooksEnable = gitHooks.enable or false;
      gitHooksHooks = if gitHooksEnable then mkDocsHook { docsDir = outDir; } else { };

      # Standalone hook content used by gitHooks.enable (for projects that do not
      # already manage hooks, e.g. via git-hooks.nix).
      gitHookScript = ''
        #!/usr/bin/env bash
        # Managed by Archinix (gitHooks.enable); regenerate with `nix develop`.
        set -euo pipefail
        root="$(git rev-parse --show-toplevel)"
        cd "$root"
        if git diff --cached --name-only | grep -qE '^(model|${outDir})(/|$)'; then
          nix run .#render -- ${outDir} --check
        fi
      '';

      gitHooksShellHook = nixpkgs.lib.optionalString gitHooksEnable ''
        _archinix_hookdir="$(git rev-parse --git-path hooks 2>/dev/null || true)"
        if [ -n "$_archinix_hookdir" ] && [ "$(git config --get core.hooksPath 2>/dev/null || true)" = "" ]; then
          if [ ! -e "$_archinix_hookdir/pre-commit" ] || grep -q archinix "$_archinix_hookdir/pre-commit" 2>/dev/null; then
            cat > "$_archinix_hookdir/pre-commit" <<'ARCHINIX_HOOK_EOF'
        ${gitHookScript}
        ARCHINIX_HOOK_EOF
            chmod +x "$_archinix_hookdir/pre-commit"
          else
            echo "[archinix] an existing pre-commit hook was found; not overwriting it." >&2
            echo "[archinix] merge \`gitHooks.hooks\` into your hook config instead." >&2
          fi
        fi
      '';
    in
    {
      packages = forAll (pkgs: (sysOf pkgs).packages);
      apps = forAll (pkgs: (sysOf pkgs).apps);
      checks = forAll (pkgs: (sysOf pkgs).checks // extraChecks pkgs);

      devShells = forAll (
        pkgs:
        let
          mermaidCli = if pkgs ? "mermaid-cli" then [ pkgs."mermaid-cli" ] else [ ];
        in
        {
          default = pkgs.mkShell {
            shellHook = gitHooksShellHook;
            packages = [
              pkgs.nixfmt
              pkgs.nixd
              pkgs.diffutils
              pkgs.findutils
            ]
            ++ mermaidCli
            ++ devShellPackages pkgs;
          };
        }
      );

      formatter = forAll (pkgs: pkgs.nixfmt);

      gitHooks = {
        hooks = gitHooksHooks;
      };
    };
in
{
  inherit
    mkOutputs
    mkSystemOutputs
    mkDocsHook
    outDirOf
    ;
}
