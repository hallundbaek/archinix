{
  description = "My architecture, defined with Archinix";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.archinix.url = "github:hallundbaek/archinix";

  outputs =
    {
      self,
      nixpkgs,
      archinix,
    }:
    archinix.lib.mkOutputs {
      inherit nixpkgs;
      model = import ./model { archinix = archinix.lib.dsl; };
      # Set `docsPath = ./docs;` once you have committed rendered docs: it
      # enables the `docs-up-to-date` check and makes `render`/`watch` use that
      # directory (override the output dir alone with `docsDir`).
    };
}
