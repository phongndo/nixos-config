_:

{
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
      ''from="100.122.138.125",restrict,pty ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII6CJnvHJlPZH22qpJR3Mhu2yoIAGpm4Y1RwUBqtiW4Z z to y over Tailscale''
    ];
  };

  # Match Hashimoto's approach: nix-darwin declares selected applications,
  # while an existing Homebrew installation owns their delivery.
  homebrew = {
    enable = true;
    casks = [
      "1password-cli"
      "aldente"
      "alfred"
      "bartender"
      "betterdisplay"
      "ghostty"
      "karabiner-elements"
      "keymapp"
      "openlogi"
      "tailscale-app"
    ];
  };
}
