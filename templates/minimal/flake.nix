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
      #
      # Install a pre-commit hook that fails when the docs are out of date
      # (only when model/ or the docs directory changes). If you already manage
      # hooks (e.g. git-hooks.nix), merge `gitHooks.hooks` into your config
      # instead and leave this off.
      gitHooks.enable = true;
    };
}
