{
  description = "Archinix: architecture-as-code. Define components and sequence diagrams in Nix, generate interlinked Mermaid markdown.";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      lib = import ./lib { inherit (nixpkgs) lib; };
      model = import ./model { archinix = lib.dsl; };

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f (import nixpkgs { inherit system; }));

      docs = pkgs: lib.renderDerivation { inherit pkgs model; };

      renderApp =
        pkgs:
        let
          docsDir = docs pkgs;
          name = "render-architecture-docs";
        in
        pkgs.writeShellApplication {
          inherit name;
          runtimeInputs = [
            pkgs.coreutils
            pkgs.diffutils
          ];
          text = ''
            set -euo pipefail
            dest="''${1:-docs}"
            mode="''${2:-}"
            src="${docsDir}"

            if [ "$mode" = "--check" ]; then
              if ! diff -ru "$src" "$dest"; then
                echo "error: generated docs are out of date; run 'nix run .#render'" >&2
                exit 1
              fi
              echo "docs are up to date"
            else
              mkdir -p "$dest"
              cp -fL "$src"/* "$dest"/
              chmod -R u+w "$dest"
              echo "wrote $(find "$dest" -maxdepth 1 -name '*.md' | wc -l) markdown file(s) to $dest"
            fi
          '';
        };

      mermaidCliApp =
        pkgs:
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
                    src="${docs pkgs}"
                    out="$(mktemp -d)"
                    status=0
                    for f in "$src"/*.md; do
                      base="$(basename "$f" .md)"
                      awk '/^```mermaid$/{flag=1;next} /^```$/{flag=0} flag' "$f" > "$out/$base.mmd"
                      if [ ! -s "$out/$base.mmd" ]; then
                        continue
                      fi
                      if err="$(mmdc -q -i "$out/$base.mmd" -o "$out/$base.svg" 2>&1)"; then
                        echo "ok: $base"
                      elif printf '%s' "$err" | grep -q "reading 'class'"; then
                        # Known mermaid-cli bug drawing actor-menu popups for some
                        # participant stereotypes; the diagram source is still valid.
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
            };
          }
        else
          { };

      # Watch `model/` and `lib/`, re-render on change, and serve the rendered
      # HTML (Markdown via python-markdown, Mermaid client-side) with browser
      # auto-reload.
      watchApp =
        pkgs:
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
            pkgs.watchexec
            pkgs.nix
            python
          ];
          text = ''
            export ARCHINIX_SERVER="${./lib/preview/server.py}"
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

            docs="$root/docs"
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
    in
    {
      inherit lib;

      packages = forAllSystems (pkgs: {
        docs = docs pkgs;
        default = docs pkgs;
      });

      apps = forAllSystems (
        pkgs:
        let
          render = "${renderApp pkgs}/bin/render-architecture-docs";
          watch = "${watchApp pkgs}/bin/archinix-watch";
        in
        mermaidCliApp pkgs
        // {
          render = {
            type = "app";
            program = render;
          };
          watch = {
            type = "app";
            program = watch;
          };
          preview = {
            type = "app";
            program = watch;
          };
          default = {
            type = "app";
            program = render;
          };
        }
      );

      checks = forAllSystems (pkgs: {
        docs-up-to-date =
          pkgs.runCommand "docs-up-to-date"
            {
              nativeBuildInputs = [ pkgs.diffutils ];
              generated = docs pkgs;
              committed = ./docs;
            }
            ''
              if ! diff -ru "$generated" "$committed"; then
                echo "error: committed docs/ differ from generated output" >&2
                exit 1
              fi
              touch $out
            '';
      });

      devShells = forAllSystems (
        pkgs:
        let
          mermaidCli = if pkgs ? "mermaid-cli" then [ pkgs."mermaid-cli" ] else [ ];
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.nixfmt
              pkgs.nixd
              pkgs.diffutils
            ]
            ++ mermaidCli;
          };
        }
      );

      formatter = forAllSystems (pkgs: pkgs.nixfmt);

      # `nix flake init -t .` copies the whole project (library + advanced
      # example model + generated docs) so it is immediately usable offline.
      templates.default = {
        path = ./.;
        description = "Archinix: Nix model -> interlinked Mermaid diagrams.";
      };
    };
}
