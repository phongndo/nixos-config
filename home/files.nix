{ config, ... }:

let
  inherit (config.lib.dotfiles) immutable writable;
in
{
  # Link helpers for this module and home/darwin.nix. Writable files link to
  # this checkout so application edits can be reviewed and committed.
  lib.dotfiles = {
    immutable = source: {
      inherit source;
      force = true;
    };
    writable = relative: {
      source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nix-config/${relative}";
      force = true;
    };
  };

  # Shared non-agent dotfiles; home/chezmoi.nix owns the agent-tool handoff.
  home.file = {
    ".bashrc".force = true;
    ".zshenv".force = true;
  };

  xdg = {
    enable = true;

    configFile = {
      "nvim/init.lua" = immutable ../config/nvim/init.lua;
      "starship.toml" = immutable ../config/starship/starship.toml;

      "btop/btop.conf" = writable "config/btop/btop.conf";
      "gh/config.yml" = writable "config/gh/config.yml";
      "nvim/lazy-lock.json" = writable "config/nvim/lazy-lock.json";
    };
  };
}
