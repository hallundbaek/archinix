{
  description = "Architecture-as-code: define components and sequence diagrams in Nix, generate interlinked Mermaid markdown.";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      lib = import ./lib { inherit (nixpkgs) lib; };
      model = import ./model;

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
        in
        mermaidCliApp pkgs
        // {
          render = {
            type = "app";
            program = render;
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
        description = "Architecture-as-code: Nix model -> interlinked Mermaid diagrams.";
      };
    };
}
