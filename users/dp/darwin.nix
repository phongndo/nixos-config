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
      # Agents and AI
      "chatgpt"
      "claude"
      "codexbar"
      "deepseek-harness"
      "devin-desktop"
      "devin-desktop@next"
      "lm-studio"
      "opencode-desktop"
      "t3-code"

      # Development
      "docker-desktop"
      "ghostty"
      "kitty"
      "mono-mdk"
      "utm"
      "visual-studio-code"
      "zed"

      # Browsers
      "google-chrome"
      "helium-browser"
      "orion"
      "zen"

      # Mac utilities
      # Manual: in 1Password, turn on Settings > Developer > Integrate with MCP
      # clients for the agents' MCP server, and set up 1Password for Claude so
      # Claude in Chrome can sign in to websites.
      "1password"
      "1password-cli"
      "aldente"
      "alfred"
      "bartender"
      "betterdisplay"
      "karabiner-elements"
      "keymapp"
      "tailscale-app"

      # Apps
      "discord"
      "fastmail"
      "figma"
      "notion"
      "obsidian"
      "sioyek"
      "skim"
      "slack"
      "spotify"
      "zoom"

      # Games
      "minecraft"
      "prismlauncher"
      "robloxstudio"
      "steam"
    ];
  };

  # Cask command-line tools, after the system's own paths, for every shell.
  environment.systemPath = lib.mkOrder 1300 [
    "/opt/homebrew/bin"
    "/opt/homebrew/sbin"
  ];
}
