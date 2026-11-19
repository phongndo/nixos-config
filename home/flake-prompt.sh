# Nix runs shellHook after shell startup. Update the indicator before each
# prompt and find the originating flake root once, using shell builtins.
_nix_update_flake_prompt() {
  if [[ -z "${IN_NIX_SHELL:-}" ]]; then
    unset NIX_FLAKE_INSIDE NIX_FLAKE_OUTSIDE
    return 0
  fi

  # direnv loads a project's shell only while you are inside that project.
  if [[ -n "${DIRENV_DIR:-}" ]]; then
    export NIX_FLAKE_INSIDE=1
    unset NIX_FLAKE_OUTSIDE
    return 0
  fi

  if [[ -z "${_NIX_FLAKE_ROOT_CAPTURED:-}" ]]; then
    local root="$PWD"
    while [[ "$root" != "/" && ! -f "$root/flake.nix" ]]; do
      root="${root%/*}"
      [[ -n "$root" ]] || root="/"
    done

    if [[ -f "$root/flake.nix" ]]; then
      export NIX_FLAKE_ROOT="$root"
    else
      unset NIX_FLAKE_ROOT
    fi
    _NIX_FLAKE_ROOT_CAPTURED=1
  fi

  if [[ -n "${NIX_FLAKE_ROOT:-}" && "$PWD/" == "$NIX_FLAKE_ROOT/"* ]]; then
    export NIX_FLAKE_INSIDE=1
    unset NIX_FLAKE_OUTSIDE
  else
    unset NIX_FLAKE_INSIDE
    export NIX_FLAKE_OUTSIDE=1
  fi
}
