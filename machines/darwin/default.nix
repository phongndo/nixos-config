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

  # Pin z's host key so unattended SSH never needs a trust-on-first-use prompt.
  programs.ssh.knownHosts.z = {
    extraHostNames = [ "100.122.138.125" ];
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAFCKBLd4XKaEVeOFk1B9nj8vt3eoo1HJ6IYagK5fvOp";
  };

  # Let nix-darwin provide the system shell and completion paths. Home Manager
  # owns the prompt and completion initialization, so do not run both twice.
  programs.zsh = {
    enable = true;
    enableBashCompletion = false;
    enableGlobalCompInit = false;
    promptInit = "";
  };
}
