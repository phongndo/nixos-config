{ pkgs, unstablePkgs, ... }:

{
  home.packages =
    (with pkgs; [
      bat
      btop
      deadnix
      eza
      fd
      ffmpeg
      fzf
      gh
      git
      git-lfs
      gnumake
      gnupg
      imagemagick
      jq
      jujutsu
      lazygit
      neovim
      nixfmt
      nixfmt-tree
      pkg-config
      python3
      ripgrep
      statix
      tmux
      zellij
      zoxide
    ])
    ++ [ unstablePkgs.llama-cpp ];
}
