{ lib, ... }:

let
  # Run the installed binary rather than mise's shim: resolving the shim costs
  # about 11 ms per shell, several times hz's own runtime. mise keeps `latest`
  # pointing at the installed release.
  hz = "$HOME/.local/share/mise/installs/github-phongndo-hz/latest/bin/hz";
in
{
  # Use the installed version's integration so mise upgrades take effect in
  # new shells without a Nix rebuild. The binaries are managed by chezmoi/mise.
  programs.zsh.initContent = lib.mkAfter ''
    if [[ -x "${hz}" ]]; then
      _hz_init="$("${hz}" shell zsh)"
      # Completion initialization belongs to the shared shell's lazy loader.
      eval "''${_hz_init/autoload -Uz compinit && compinit/:}"
      unset _hz_init
    fi
  '';
  programs.bash.initExtra = lib.mkAfter ''
    if [[ -x "${hz}" ]]; then
      eval "$("${hz}" shell bash)"
    fi
  '';
}
