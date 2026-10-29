# Home Manager modules shared by y and z. Platform-only settings live in
# darwin.nix and linux.nix.
_:

{
  imports = [
    ./chezmoi.nix
    ./files.nix
    ./packages.nix
    ./shell.nix
  ];

  home.stateVersion = "26.05";

  # Avoid Home Manager's contextless options.json derivation under Determinate Nix.
  manual.manpages.enable = false;

  programs.home-manager.enable = true;
}
