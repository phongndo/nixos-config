# Home Manager settings for NixOS z only.
{
  hosts,
  inputs,
  lib,
  pkgs,
  ...
}:

{
  imports = [ inputs.rex.homeManagerModules.default ];

  services.rex = {
    enable = true;
    # Use z's existing tailnet identity; Rex admits its owner.
    # Manual: in Rex on y, add http://<z's address in hosts.nix>:7297 as remote
    # host z. Use the IPv4 address; Rex's hostname/IPv6 path fails to load terminals.
    extraListen = [ "tailnet://:7297" ];
  };

  # Shared previews: a read-only static server for ~/.local/share/previews on
  # z's tailnet address only. Linger keeps it running across logins and
  # reboots, and it retries until Tailscale has the address up.
  systemd.user.services.previews = {
    Unit.Description = "Shared previews";
    Service = {
      # Keep directory listings: miniserve's automatic --index selection follows
      # symlinked indexes despite --no-symlinks. Link to explicit HTML files.
      ExecStart = lib.concatStringsSep " " [
        (lib.getExe pkgs.miniserve)
        "--interfaces ${hosts.z.address} --port 8765"
        "--no-symlinks --dirs-first --title Previews --hide-version-footer"
        "%h/.local/share/previews"
      ];
      Restart = "always";
      RestartSec = 5;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = "read-only";
      ProtectSystem = "strict";
    };
    Install.WantedBy = [ "default.target" ];
  };
  systemd.user.tmpfiles.rules = [ "d %h/.local/share/previews 0700 - - -" ];

  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    settings.y = {
      HostName = hosts.y.address;
      User = "dp";
      IdentityFile = "~/.ssh/id_ed25519_y";
      IdentitiesOnly = true;
    };
  };

  home.packages = with pkgs; [
    # macOS gets 1Password CLI through Homebrew.
    _1password-cli
    # Native toolchain for T3 Code's npm/node-pty builds (Node itself stays on mise).
    # On macOS it would shadow Xcode's cc/c++; use Xcode or a development shell.
    gcc
    # Headless virtual GUI over SSH; no desktop environment or display manager.
    xpra
    xterm
    xvfb

    # T3 Code's desktop app self-updates; update this server to match in place.
    (writeShellApplication {
      name = "t3-update";
      runtimeInputs = [ jq ];
      text = ''
        version="$(jq -er .activeVersion "$HOME/.t3/runtime/service-state.json")"
        exec "$HOME/.t3/runtime/versions/$version/t3" update --yes "$@"
      '';
    })
  ];
}
