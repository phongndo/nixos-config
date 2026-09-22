{
  pkgs,
  lib,
  unstablePkgs,
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
    # Neovim language servers and companions. Keep nvim/init.lua in sync.
    # Project development shells can put matching server/toolchain versions first on PATH.
    ++ (with pkgs; [
      bash-language-server
      clang-tools # clangd for C / C++
      nixd
      ocamlPackages.ocaml-lsp
      ocamlformat # ocamlformat-rpc is used for OCaml hover formatting
      pyright
      rust-analyzer
      typescript-language-server # JavaScript / TypeScript / JSX / TSX
      vscode-langservers-extracted # HTML / CSS / JSON (no extra ESLint diagnostics)
      yaml-language-server
      zig # ZLS needs the compiler and standard library; use a matching project version.
      zls
    ])
    ++ [ unstablePkgs.llama-cpp ]
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
