{
  config,
  lib,
  pkgs,
  ...
}:

let
  configRoot = "${config.home.homeDirectory}/nix-config";
  alfredWorkflow = "Library/Application Support/Alfred/Alfred.alfredpreferences/workflows/user.workflow.63D398BB-A391-40E9-B356-24123A2B339E";

  immutable = source: {
    inherit source;
    force = true;
  };

  writable = relative: {
    source = config.lib.file.mkOutOfStoreSymlink "${configRoot}/${relative}";
    force = true;
  };
in
{
  # Non-agent dotfiles only; home/chezmoi.nix owns the agent-tool handoff.
  home = {
    file = lib.mkMerge [
      {
        ".bashrc".force = true;
        ".zshenv" = immutable ./zshenv;
      }

      (lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
        # Alfred owns the workflow directory. Link its editable source files
        # individually so activation never has to replace that directory.
        "${alfredWorkflow}/focus-window.sh" = writable "alfred/appfocus/focus-window.sh";
        "${alfredWorkflow}/info.plist" = writable "alfred/appfocus/info.plist";
        "${alfredWorkflow}/list-windows.sh" = writable "alfred/appfocus/list-windows.sh";
      })
    ];
  };

  xdg = {
    enable = true;

    configFile = lib.mkMerge [
      {
        "nvim/init.lua" = immutable ../nvim/init.lua;
        "starship.toml" = immutable ../starship/starship.toml;

        "btop/btop.conf" = writable "btop/btop.conf";
        "gh/config.yml" = writable "gh/config.yml";
        "nvim/lazy-lock.json" = writable "nvim/lazy-lock.json";
      }

      (lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
        "ghostty/config" = immutable ../ghostty/config;
        "ghostty/themes/mono" = immutable ../ghostty/themes/mono;
        "karabiner/karabiner.json" = writable "karabiner/karabiner.json";
        "launchd/skhd-runner" = immutable ../launchd/skhd-runner;
        "launchd/yabai-runner" = immutable ../launchd/yabai-runner;
        "skhd/focus-previous-app" = immutable ../skhd/focus-previous-app;
        "skhd/skhdrc" = (immutable ../skhd/skhdrc) // {
          # skhd's watcher can miss Home Manager replacing a Nix-store symlink.
          # Reload after linking the new config; leave stopped daemons stopped.
          onChange = ''
            if /usr/bin/pgrep -u "$(/usr/bin/id -u)" -x skhd >/dev/null; then
              ${lib.getExe pkgs.skhd} --reload
            fi
          '';
        };
        "yabai/apps.tsv" = immutable ../yabai/apps.tsv;
        "yabai/focus-bundle" = immutable ../yabai/focus-bundle;
        "yabai/focus-or-open" = immutable ../yabai/focus-or-open;
        "yabai/focus-space" = immutable ../yabai/focus-space;
        "yabai/move-window-to-space" = immutable ../yabai/move-window-to-space;
        "yabai/safe-yabai" = immutable ../yabai/safe-yabai;
        "yabai/yabairc" = immutable ../yabai/yabairc;
      })
    ];
  };
}
