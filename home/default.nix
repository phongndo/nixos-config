_:

{
  imports = [
    ./chezmoi.nix
    ./files.nix
    ./packages.nix
    ./personal-projects.nix
    ./shell.nix
  ];

  home.stateVersion = "26.05";

  # Avoid Home Manager's contextless options.json derivation under Determinate Nix.
  manual.manpages.enable = false;

  programs.home-manager.enable = true;
}
