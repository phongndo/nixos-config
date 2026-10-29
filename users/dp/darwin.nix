{ hosts, lib, ... }:

{
  # macOS owns the admin account's login shell (/bin/zsh); nix-darwin manages
  # account fields only for users it creates.
  imports = [ ./shell.nix ];

  system = {
    primaryUser = "dp";

    defaults = {
      NSGlobalDomain = {
        AppleInterfaceStyle = "Dark";
        InitialKeyRepeat = 15;
        KeyRepeat = 2;
      };

      dock = {
        autohide = true;
        show-recents = false;
      };

      trackpad.Clicking = true;
    };
  };

  users.users.dp = {
    home = "/Users/dp";
    # Dedicated z -> y login key. The unencrypted private key stays on z;
    # permit interactive SSH only from z's tailnet address, without forwarding.
    openssh.authorizedKeys.keys = [
      ''from="${hosts.z.address}",restrict,pty ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII6CJnvHJlPZH22qpJR3Mhu2yoIAGpm4Y1RwUBqtiW4Z z to y over Tailscale''
    ];
  };

  # nix-darwin declares every Homebrew app; the existing Homebrew installation
  # delivers them, and activation uninstalls anything not listed here.
  homebrew = {
    enable = true;
    onActivation.cleanup = "uninstall";
    casks = [
      "1password"
      "1password-cli"
      "aldente"
      "alfred"
      "bartender"
      "betterdisplay"
      "chatgpt"
      "claude"
      "codexbar"
      "deepseek-harness"
      "devin-desktop"
      "devin-desktop@next"
      "discord"
      "docker-desktop"
      "fastmail"
      "figma"
      "ghostty"
      "google-chrome"
      "helium-browser"
      "karabiner-elements"
      "keymapp"
      "kitty"
      "lm-studio"
      "minecraft"
      "mono-mdk"
      "notion"
      "obsidian"
      "opencode-desktop"
      "orion"
      "prismlauncher"
      "robloxstudio"
      "sioyek"
      "skim"
      "slack"
      "spotify"
      "steam"
      "t3-code"
      "tailscale-app"
      "utm"
      "visual-studio-code"
      "zed"
      "zen"
      "zoom"
    ];
  };

  # Cask command-line tools, after the system's own paths, for every shell.
  environment.systemPath = lib.mkOrder 1300 [
    "/opt/homebrew/bin"
    "/opt/homebrew/sbin"
  ];
}
