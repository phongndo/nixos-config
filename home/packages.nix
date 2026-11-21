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
    # Neovim language servers, used outside project shells. Keep
    # config/nvim/init.lua in sync. Development shells put toolchain-matched
    # servers (clangd, rust-analyzer, zls, mlir-lsp-server) first on PATH.
    ++ (with pkgs; [
      bash-language-server
      lua-language-server
      nixd
      pyright
      rust-analyzer # On y, rustup's ~/.cargo/bin/rust-analyzer comes first.
      typescript-language-server # JavaScript / TypeScript / JSX / TSX
      vscode-langservers-extracted # CSS / JSON (no extra ESLint diagnostics)
    ])
    # The Mac uses Xcode's /usr/bin/clangd outside project shells: nixpkgs'
    # can't find Xcode's libc++ there.
    ++ pkgs.lib.optionals pkgs.stdenv.isLinux [ pkgs.clang-tools ]
    ++ [ unstablePkgs.llama-cpp ];
}
