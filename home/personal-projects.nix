{ lib, ... }:

{
  # Use the installed version's integration so mise upgrades take effect in
  # new shells without a Nix rebuild. The binaries are managed by chezmoi/mise.
  programs.zsh.initContent = lib.mkAfter ''
    if command -v hz >/dev/null 2>&1; then
      _hz_init="$(command hz shell zsh)"
      # Completion initialization belongs to the shared shell's lazy loader.
      eval "''${_hz_init/autoload -Uz compinit && compinit/:}"
      unset _hz_init
    fi
  '';
  programs.bash.initExtra = lib.mkAfter ''
    if command -v hz >/dev/null 2>&1; then
      eval "$(command hz shell bash)"
    fi
  '';
}
