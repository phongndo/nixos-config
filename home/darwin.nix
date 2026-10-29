# Home Manager settings for macOS y only.
{
  config,
  hosts,
  lib,
  pkgs,
  ...
}:

let
  inherit (config.lib.dotfiles) immutable writable;
  home = config.home.homeDirectory;
  alfredWorkflow = "Library/Application Support/Alfred/Alfred.alfredpreferences/workflows/user.workflow.63D398BB-A391-40E9-B356-24123A2B339E";

  # launchd restarts the daemon after any exit: at login it can exit cleanly
  # before Accessibility or Secure Keyboard Entry is ready. Home Manager waits
  # for the Nix store before starting it.
  agent = name: args: {
    enable = true;
    config = {
      Label = "com.dp.${name}";
      ProgramArguments = [ (lib.getExe pkgs.${name}) ] ++ args;
      EnvironmentVariables = {
        PATH = "${config.home.profileDirectory}/bin:/usr/bin:/bin:/usr/sbin:/sbin";
        # skhd runs bindings through "$SHELL -c"; keep hotkeys off user shell startup.
        SHELL = "/bin/bash";
      };
      KeepAlive = true;
      ProcessType = "Interactive";
      RunAtLoad = true;
      ThrottleInterval = 5;
      StandardOutPath = "${home}/Library/Logs/${name}.log";
      StandardErrorPath = "${home}/Library/Logs/${name}.log";
    };
  };
in
{
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    settings = {
      "github.com" = {
        IdentityFile = "~/.ssh/id_ed25519";
        AddKeysToAgent = "yes";
        UseKeychain = "yes";
      };

      z = {
        HostName = hosts.z.address;
        User = "dp";
        IdentityFile = "~/.ssh/id_ed25519";
        IdentitiesOnly = true;
        AddKeysToAgent = "yes";
        UseKeychain = "yes";
      };
    };
  };

  programs.browserpass = {
    enable = true;
    browsers = [ "chrome" ];
  };

  home = {
    packages = with pkgs; [
      browserpass
      pass
      pinentry_mac
      skhd
      yabai
      # T3 Code's desktop app self-updates; z's server must match its version.
      (writeShellScriptBin "t3-update" ''exec ssh z t3-update "$@"'')
    ];

    sessionPath = lib.mkAfter [ "$HOME/.lmstudio/bin" ];

    # Alfred owns the workflow directory. Link its editable source files
    # individually so activation never has to replace that directory.
    file = {
      "${alfredWorkflow}/focus-window.sh" = writable "config/alfred/appfocus/focus-window.sh";
      "${alfredWorkflow}/info.plist" = writable "config/alfred/appfocus/info.plist";
      "${alfredWorkflow}/list-windows.sh" = writable "config/alfred/appfocus/list-windows.sh";
    };
  };

  xdg.configFile = {
    "ghostty/config" = immutable ../config/ghostty/config;
    "ghostty/themes/mono" = immutable ../config/ghostty/themes/mono;
    "karabiner/karabiner.json" = writable "config/karabiner/karabiner.json";
    "skhd/focus-app" = immutable ../config/skhd/focus-app;
    "skhd/mark" = immutable ../config/skhd/mark;
    "skhd/skhdrc" = (immutable ../config/skhd/skhdrc) // {
      # skhd's watcher can miss Home Manager replacing a Nix-store symlink.
      # Reload after linking the new config; leave stopped daemons stopped.
      onChange = ''
        if /usr/bin/pgrep -u "$(/usr/bin/id -u)" -x skhd >/dev/null; then
          ${lib.getExe pkgs.skhd} --reload
        fi
      '';
    };
    "yabai/yabairc" = immutable ../config/yabai/yabairc;
  };

  launchd.agents = {
    skhd = agent "skhd" [
      "-c"
      "${config.xdg.configHome}/skhd/skhdrc"
    ];
    yabai = agent "yabai" [
      "--config"
      "${config.xdg.configHome}/yabai/yabairc"
    ];
  };
}
