{ pkgs, unstablePkgs, ... }:

{
  home.packages =
    (with pkgs; [
      bat
      btop
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
      pkg-config
      python3
      ripgrep
      tmux
      tree-sitter # Builds Neovim's syntax parsers.
      zellij
      zoxide
    ])
    ++ [ unstablePkgs.llama-cpp ];
}
