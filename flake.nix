{
  description = "Archinix: architecture-as-code. Define components and sequence diagrams in Nix, generate interlinked Mermaid markdown.";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      lib = import ./lib { inherit (nixpkgs) lib; };
      model = import ./model { archinix = lib.dsl; };
    in
    lib.mkOutputs {
      inherit nixpkgs model;
      docsPath = ./docs;
    }
    // {
      inherit lib;

      templates = {
        # Minimal project: only `flake.nix` + `model/`; Archinix is a flake input.
        minimal = {
          path = ./templates/minimal;
          description = "Minimal Archinix project (Archinix imported as a flake input; only model/ needed).";
        };
        # Self-contained project: the library, example model and generated docs.
        selfcontained = {
          path = ./.;
          description = "Self-contained Archinix project (library + example model + docs).";
        };
        default = self.templates.minimal;
      };
    };
}
