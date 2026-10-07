# flake-parts module. Exposed as `archinix.flakeModules.default`; import it in a
# flake-parts flake and configure it under `perSystem.archinix`.
archinix:
{
  lib,
  flake-parts-lib,
  ...
}:
let
  mkOptions =
    { lib, ... }:
    {
      options.archinix = {
        model = lib.mkOption {
          type = lib.types.raw;
          description = "The Archinix model (e.g. `import ./model { archinix = inputs.archinix.lib.dsl; }`).";
        };
        docsPath = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "Committed docs directory; enables the docs-up-to-date check and sets the output directory.";
        };
        docsDir = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Output directory for `render`/`watch` (defaults to `docsPath`'s name).";
        };
        markdownFormatter = lib.mkOption {
          type = lib.types.nullOr lib.types.raw;
          default = null;
          description = "`{ pkgs, src }: derivation` run over the rendered docs.";
        };
        name = lib.mkOption {
          type = lib.types.str;
          default = "architecture-docs";
          description = "Derivation name for the generated docs.";
        };
        gitHooks.enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Add the docs-up-to-date hook (import `archinix.flakeModules.gitHooks` too).";
        };
        gitHooks.hooks = lib.mkOption {
          type = lib.types.attrs;
          default = { };
          description = "The docs-up-to-date hook definition, for manual merging into any hook config.";
        };
        lib = lib.mkOption {
          type = lib.types.raw;
          readOnly = true;
          default = archinix;
          description = "The Archinix library (so `archinix.model` can use `config.archinix.lib.dsl`).";
        };
      };
    };
in
{
  options.perSystem = flake-parts-lib.mkPerSystemOption mkOptions;

  config.perSystem =
    {
      pkgs,
      config,
      ...
    }:
    let
      cfg = config.archinix;
      outDir = archinix.outDirOf { inherit (cfg) docsDir docsPath; };
      sys = archinix.mkSystemOutputs {
        inherit pkgs;
        model = cfg.model;
        docsPath = cfg.docsPath;
        docsDir = cfg.docsDir;
        markdownFormatter = cfg.markdownFormatter;
        name = cfg.name;
      };
    in
    {
      inherit (sys)
        packages
        apps
        checks
        ;
      archinix.gitHooks.hooks = archinix.mkDocsHook { docsDir = outDir; };
    };
}
