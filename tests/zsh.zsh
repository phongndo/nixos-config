# Source from a configured interactive Zsh: source ./tests/zsh.zsh
() {
  [[ -o interactive ]] || { print -u2 'Run this check in interactive Zsh'; return 1; }

  [[ $(bindkey '^G') == *edit-command-line ]] || return 1
  [[ $VISUAL == nvim ]] && whence -p nvim >/dev/null || return 1

  local -A history_bindings
  local keymap
  for keymap in emacs viins vicmd; do
    history_bindings[$keymap]=$(bindkey -M "$keymap" '^R')
  done
  [[ ${history_bindings[emacs]} == *atuin* ]] || return 1
  [[ ${history_bindings[viins]} == *atuin* ]] || return 1

  _load_shell_completions || return 1
  (( $+functions[compdef] )) || return 1
  [[ $(bindkey '^T') == *fzf-file-widget ]] || return 1
  [[ $(bindkey '^G') == *edit-command-line ]] || return 1
  for keymap in emacs viins vicmd; do
    [[ $(bindkey -M "$keymap" '^R') == ${history_bindings[$keymap]} ]] || return 1
  done

  # Repeated completion must not repeat initialization or change key bindings.
  local completion_binding=$(bindkey '^I')
  local -a completion_paths=("${fpath[@]}")
  _load_shell_completions || return 1
  [[ $(bindkey '^I') == "$completion_binding" ]] || return 1
  [[ ${(j.:.)fpath} == ${(j.:.)completion_paths} ]] || return 1

  print 'Zsh checks passed: completion, Atuin Ctrl-R, FZF Ctrl-T, Neovim Ctrl-G.'
}
