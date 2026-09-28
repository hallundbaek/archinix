{
  description = "My architecture, defined with Archinix";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.archinix.url = "github:hallundbaek/archinix";

  outputs =
    { self, nixpkgs, archinix }:
    archinix.lib.mkOutputs {
      inherit nixpkgs;
      model = import ./model { archinix = archinix.lib.dsl; };
      # Add `docsPath = ./docs;` once you have committed rendered docs to enable
      # the `docs-up-to-date` check.
    };
}
