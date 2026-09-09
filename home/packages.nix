{
  pkgs,
  lib,
  ...
}:

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
      # Native toolchain for T3 Code's npm/node-pty builds (Node itself stays on mise).
      gcc
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
      nixd
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
    # Linux-only packages; macOS gets 1Password CLI through Homebrew.
    ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux (
      with pkgs;
      [
        _1password-cli
        # Headless virtual GUI over SSH; no desktop environment or display manager.
        xpra
        xterm
        xvfb
      ]
    );
}
