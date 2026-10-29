_:

{
  # Determinate manages the installed Nix daemon and store. nix-darwin owns
  # the surrounding macOS configuration without replacing that installation.
  nix.enable = false;

  # Determinate's daemon merges these into Nix's netrc, so y can fetch z's Rex
  # input. Manual: copy z's /etc/determinate/rex.netrc here (root, mode 0600)
  # before switching.
  environment.etc."determinate/config.json".text = builtins.toJSON {
    authentication.additionalNetrcSources = [ "/etc/determinate/rex.netrc" ];
  };

  system.stateVersion = 6;

  networking = {
    hostName = "y";
    computerName = "y";
  };

  services.openssh.enable = true;
}
