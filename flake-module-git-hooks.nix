# flake-parts module for git-hooks.nix. Import it (alongside
# `archinix.flakeModules.default` and `inputs.git-hooks-nix.flakeModule`) to add
# the docs-up-to-date hook to your existing `perSystem.pre-commit` set.
{ lib, ... }:
{
  config.perSystem =
    { config, lib, ... }:
    {
      pre-commit.settings.hooks = lib.mkIf config.archinix.gitHooks.enable config.archinix.gitHooks.hooks;
    };
}
