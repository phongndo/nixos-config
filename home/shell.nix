{
  config,
  lib,
  configurationName,
  rebuildCommand,
  pkgs,
  ...
}:

let
  # Rex supplies its CLI directory separately from PATH. Restore it after shell
  # setup so this works with local and remote Rex servers on any host.
  rexShellInit = ''
    if [[ -n "''${REX_BIN_DIR:-}" ]]; then
      export PATH="$REX_BIN_DIR:$PATH"
    fi
  '';

  # hz follows mise rather than Nix. Cache its integration and regenerate it
  # only after mise changes the install directory, instead of running hz on
  # every startup. The integration calls `hz` through PATH, so the cache
  # survives pruning old versions.
  hzDir = "$HOME/.local/share/mise/installs/github-phongndo-hz";
  hzInit = shell: write: ''
    _hz_dir="${hzDir}"
    _hz_cache="''${XDG_CACHE_HOME:-$HOME/.cache}/hz/init.${shell}"
    if [[ -x "$_hz_dir/latest/bin/hz" ]]; then
      if [[ ! -s "$_hz_cache" || "$_hz_dir" -nt "$_hz_cache" ]]; then
        [[ -d "''${_hz_cache%/*}" ]] || mkdir -p "''${_hz_cache%/*}"
        ${write} && mv -f "$_hz_cache.$$" "$_hz_cache" || rm -f "$_hz_cache.$$"
      fi
      [[ -s "$_hz_cache" ]] && source "$_hz_cache"
    fi
    unset _hz_dir _hz_cache _hz_init
  '';

  # Generate static integrations at build time instead of on every startup.
  mkShellInit =
    name: command:
    pkgs.runCommand name { } ''
      export HOME="$TMPDIR/home"
      export XDG_CONFIG_HOME="$TMPDIR/config"
      export XDG_DATA_HOME="$TMPDIR/data"
      mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME"
      ${command} > "$out"
    '';
  starshipExe = lib.getExe config.programs.starship.package;
  starshipBashInit = pkgs.runCommand "starship-bash-init" { } ''
    export HOME="$TMPDIR/home"
    export XDG_CONFIG_HOME="$TMPDIR/config"
    mkdir -p "$HOME" "$XDG_CONFIG_HOME"
    ${starshipExe} init bash --print-full-init > "$out"

    # Bash 5 exposes a microsecond clock, so avoid spawning Starship just to
    # record timestamps. Keep the original command as a fallback for Bash 3.
    substituteInPlace "$out" \
      --replace-fail 'STARSHIP_START_TIME=$(${starshipExe} time)' '_starship_now; STARSHIP_START_TIME=$REPLY' \
      --replace-fail 'STARSHIP_END_TIME=$(${starshipExe} time)' '_starship_now; STARSHIP_END_TIME=$REPLY'
    ${lib.getExe pkgs.gnused} -i '/^PS2=/d' "$out"
    {
      cat <<'EOF'
    _starship_now() {
      if [[ -n ''${EPOCHREALTIME:-} ]]; then
        REPLY=''${EPOCHREALTIME/./}
        REPLY=''${REPLY:0:13}
      else
        REPLY=$(${starshipExe} time)
      fi
    }
    EOF
      cat "$out"
    } > "$TMPDIR/init"
    mv "$TMPDIR/init" "$out"

    continuation="$(STARSHIP_SHELL=bash STARSHIP_CONFIG=${../config/starship/starship.toml} ${starshipExe} prompt --continuation)"
    LC_ALL=C printf 'PS2=%q\n' "$continuation" >> "$out"
  '';
  starshipZshInit = pkgs.runCommand "starship-zsh-init" { } ''
    export HOME="$TMPDIR/home"
    export XDG_CONFIG_HOME="$TMPDIR/config"
    mkdir -p "$HOME" "$XDG_CONFIG_HOME"
    ${starshipExe} init zsh > "$out"

    # The continuation prompt is configuration-only; render it once at build
    # time instead of spawning Starship during every shell startup.
    ${lib.getExe pkgs.gnused} -i '/^PROMPT2=/d' "$out"
    continuation="$(STARSHIP_SHELL=zsh STARSHIP_CONFIG=${../config/starship/starship.toml} ${starshipExe} prompt --continuation)"
    LC_ALL=C printf 'PROMPT2=%q\n' "$continuation" >> "$out"
  '';
  zoxideBashInit = mkShellInit "zoxide-bash-init" "${lib.getExe pkgs.zoxide} init bash";
  zoxideZshInit = mkShellInit "zoxide-zsh-init" "${lib.getExe pkgs.zoxide} init zsh";
in
{
  home = {
    # Set once per login session for every shell and its children. A Nix
    # development shell inherits these and puts its own PATH first.
    sessionPath = [
      "$HOME/.local/share/mise/shims"
      "$HOME/.cargo/bin"
      "$HOME/.local/bin"
    ];
    sessionVariables = {
      EDITOR = "nvim";
      VISUAL = "nvim";
    };

    shellAliases = {
      ls = "${lib.getExe pkgs.eza} --group-directories-first";

      # Git operations in this repository.
      dot = "git -C \"$HOME/nix-config\"";

      # Rebuild the complete host; Home Manager is part of the system generation.
      hm = "sudo ${rebuildCommand} switch --flake \"$HOME/nix-config#${configurationName}\"";
    };
  };

  programs = {
    zsh = {
      enable = true;
      enableCompletion = true;
      history.path = "$HOME/.zsh_history";

      # Keep the completion package, but defer compinit and FZF's completion
      # parser until the first Tab or Ctrl-T press below.
      completionInit = "";

      initContent = lib.mkMerge [
        (lib.mkOrder 900 ''
          # Home Manager creates the history parent on every startup. Its parent
          # already exists, so implement that one check with Zsh builtins.
          # Home Manager 26.11 checks first itself; delete this shim with it.
          dirname() {
            if (( $# == 1 )); then
              print -r -- "''${1:h}"
            else
              command dirname "$@"
            fi
          }
          mkdir() {
            if (( $# == 2 )) && [[ "$1" == -p && -d "$2" ]]; then
              return 0
            fi
            command mkdir "$@"
          }
        '')
        (lib.mkOrder 920 ''
          unfunction dirname mkdir
        '')
        (builtins.readFile ./zshrc)
        (lib.mkAfter ''
          source ${zoxideZshInit}
          source ${starshipZshInit}

          if [[ $options[zle] = on ]]; then
            export FZF_CTRL_T_OPTS="--preview 'bat --style=numbers --color=always {}'"
            fzf_default_completion=expand-or-complete

            # Completion setup is invisible until it is needed. The first call
            # also registers zoxide's and hz's completions, defined below.
            _load_shell_completions() {
              (( ''${_shell_completions_loaded:-0} )) && return 0

              # Nix profiles can contribute several symlinks to the same target.
              local -A seen
              local -a unique
              local dir real
              for dir in $fpath; do
                [[ -d "$dir" ]] || continue
                real="''${dir:A}"
                [[ -n "''${seen[$real]-}" ]] && continue
                seen[$real]=1
                unique+=("$dir")
              done
              fpath=("''${unique[@]}")

              autoload -Uz compinit
              local cache_dir="''${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
              [[ -d "$cache_dir" ]] || mkdir -p "$cache_dir"
              local user_profile="/etc/profiles/per-user/${config.home.username}"
              local system_profile="/run/current-system/sw"
              local nix_profile="/nix/var/nix/profiles/default"
              local dump="$cache_dir/zcompdump-$ZSH_VERSION-''${user_profile:A:t}-''${system_profile:A:t}-''${nix_profile:A:t}"
              compinit -C -d "$dump"
              if [[ ! -s "$dump.zwc" || "$dump" -nt "$dump.zwc" ]]; then
                zcompile "$dump"
              fi
              (( $+functions[__zoxide_z_complete] )) && compdef __zoxide_z_complete z
              (( $+functions[_hz_complete] )) && compdef _hz_complete hz _hz
              # Keep Ctrl-R on native history search and leave directory
              # navigation to zoxide.
              local FZF_CTRL_R_COMMAND="" FZF_ALT_C_COMMAND=""
              source ${pkgs.fzf}/share/fzf/key-bindings.zsh
              source ${pkgs.fzf}/share/fzf/completion.zsh
              bindkey -r '^[c'
              typeset -g _shell_completions_loaded=1
            }
            _fzf_lazy_file_widget() {
              _load_shell_completions
              zle fzf-file-widget
            }
            _fzf_lazy_completion() {
              _load_shell_completions
              zle fzf-completion
            }
            zle -N fzf-lazy-file-widget _fzf_lazy_file_widget
            zle -N fzf-lazy-completion _fzf_lazy_completion
            bindkey '^T' fzf-lazy-file-widget
            bindkey '^I' fzf-lazy-completion
            bindkey -r '^[c'
          fi

          # hz's completion initialization belongs to the lazy loader above.
          ${hzInit "zsh" ''_hz_init="$("$_hz_dir/latest/bin/hz" shell zsh)" && print -r -- "''${_hz_init/autoload -Uz compinit && compinit/:}" >| "$_hz_cache.$$"''}
        '')
        (lib.mkOrder 2000 rexShellInit)
      ];
    };

    # Keep Bash aligned with Zsh: same session environment, aliases,
    # integrations, and Starship prompt.
    bash = {
      enable = true;
      # Load Bash and FZF completion together on the first Tab press.
      enableCompletion = false;
      historyControl = [
        "ignoredups"
        "ignorespace"
      ];
      shellOptions = [
        "checkwinsize"
        "histappend"
      ];
      initExtra = lib.mkMerge [
        (builtins.readFile ./bashrc)
        (lib.mkAfter ''
          source ${zoxideBashInit}

          if [[ :$SHELLOPTS: =~ :(vi|emacs): ]]; then
            export FZF_CTRL_T_OPTS="--preview 'bat --style=numbers --color=always {}'"
            source ${pkgs.fzf}/share/fzf/key-bindings.bash

            # Queue a normal Tab after this one-shot Readline macro loads both
            # completion frameworks. This preserves first-Tab behavior. The
            # rebind runs on every invocation because a system bashrc may have
            # loaded bash-completion already, so BASH_COMPLETION_VERSINFO can't
            # be the sentinel; without the rebind, Tab would stay bound to this
            # macro and recurse until Readline gives up.
            _load_shell_completions() {
              if [[ -z "''${_BASH_LAZY_COMPLETIONS_LOADED:-}" ]]; then
                _BASH_LAZY_COMPLETIONS_LOADED=1
                if [[ -z "''${BASH_COMPLETION_VERSINFO:-}" ]]; then
                  source ${pkgs.bash-completion}/etc/profile.d/bash_completion.sh
                fi
                source ${pkgs.fzf}/share/fzf/completion.bash
              fi
              bind -m emacs-standard '"\C-i": complete'
              bind -m vi-insert '"\C-i": complete'
            }
            bind -m emacs-standard -x '"\C-x\C-]": _load_shell_completions'
            bind -m emacs-standard '"\C-i": "\C-x\C-]\C-i"'
            bind -m vi-insert -x '"\C-x\C-]": _load_shell_completions'
            bind -m vi-insert '"\C-i": "\C-x\C-]\C-i"'

            # Starship hooks into bash-preexec, avoiding a process per command.
            source ${pkgs.bash-preexec}/share/bash/bash-preexec.sh
          fi

          if [[ $TERM != "dumb" ]]; then
            source ${starshipBashInit}
          fi

          ${hzInit "bash" ''"$_hz_dir/latest/bin/hz" shell bash >| "$_hz_cache.$$"''}
        '')
        (lib.mkOrder 2000 rexShellInit)
      ];
    };

    # Both shells source build-time-generated Starship initialization above.
    starship = {
      enable = true;
      enableZshIntegration = false;
      enableBashIntegration = false;
    };
  };
}
