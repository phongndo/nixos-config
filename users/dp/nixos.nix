{ pkgs, ... }:

{
  imports = [ ./shell.nix ];

  users.users.dp = {
    isNormalUser = true;
    # Preserve ownership of the existing Linux home and data after renaming z.
    uid = 1000;
    # Start user services at boot, independent of interactive logins.
    linger = true;
    description = "phony";
    shell = pkgs.zsh;
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII7YFAmCVuAcrXuYzE/A47ceCoW8ZflRM/qpUK1nU+oT phongndo69@gmail.com"
    ];
  };

  # Home Manager loads completion on the first Tab and lists with eza, so skip
  # the system's eager bash-completion and per-shell dircolors.
  programs = {
    bash = {
      completion.enable = false;
      enableLsColors = false;
    };
    zsh.enableLsColors = false;
  };
}
