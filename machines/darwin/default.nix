_:

{
  # Determinate manages the installed Nix daemon and store. nix-darwin owns
  # the surrounding macOS configuration without replacing that installation.
  nix.enable = false;

  system.stateVersion = 6;

  networking = {
    hostName = "y";
    computerName = "y";
  };

  services.openssh.enable = true;
}
