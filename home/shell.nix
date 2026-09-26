{
  config,
  lib,
  configurationName,
  rebuildCommand,
  unstablePkgs,
  pkgs,
  ...
}:

let
  mkShellInit =
    name: command:
    pkgs.runCommand name { } ''
      export HOME="$TMPDIR/home"
      export XDG_CONFIG_HOME="$TMPDIR/config"
      export XDG_DATA_HOME="$TMPDIR/data"
      mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME"
      ${command} > "$out"
    '';

  atuinPtyZshInit = pkgs.runCommand "atuin-pty-zsh-init" { } ''
    ${lib.getExe config.programs.atuin.package} pty-proxy init zsh \
      | ${lib.getExe pkgs.gnused} 's|--shell "''${_atuin_pty_proxy_zsh#-}"|--shell "$(command -v zsh)"|' \
      > "$out"
  '';
  atuinBashInit = mkShellInit "atuin-bash-init" "${lib.getExe config.programs.atuin.package} init bash";
  atuinZshInit = mkShellInit "atuin-zsh-init" "${lib.getExe config.programs.atuin.package} init zsh";
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

    continuation="$(STARSHIP_SHELL=bash STARSHIP_CONFIG=${../starship/starship.toml} ${starshipExe} prompt --continuation)"
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
    continuation="$(STARSHIP_SHELL=zsh STARSHIP_CONFIG=${../starship/starship.toml} ${starshipExe} prompt --continuation)"
    LC_ALL=C printf 'PROMPT2=%q\n' "$continuation" >> "$out"
  '';
  zoxideBashInit = mkShellInit "zoxide-bash-init" "${lib.getExe pkgs.zoxide} init bash";
  zoxideZshInit = mkShellInit "zoxide-zsh-init" "${lib.getExe pkgs.zoxide} init zsh";
in
{
  home.shellAliases = {
    ls = "${lib.getExe pkgs.eza} --group-directories-first";

    # Git operations in this repository.
    dot = "git -C \"$HOME/nix-config\"";

    # Rebuild the complete host; Home Manager is part of the system generation.
    hm = "sudo ${rebuildCommand} switch --flake \"$HOME/nix-config#${configurationName}\"";
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
        (lib.mkBefore ''
          # Run Atuin's PTY proxy before the regular shell integration so recent
          # command output is available to Atuin AI through the daemon. Generate
          # this static shell code at build time rather than on every startup.
          # The patch works around atuin#3606 for SSH login shells.
          source ${atuinPtyZshInit}
        '')
        (lib.mkOrder 900 ''
          # Home Manager creates the history parent on every startup. Its parent
          # already exists, so implement that one check with Zsh builtins.
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
          # Source static integrations generated during the Nix build.
          source ${zoxideZshInit}
          source ${starshipZshInit}

          if [[ $options[zle] = on ]]; then
            export FZF_CTRL_T_OPTS="--preview 'bat --style=numbers --color=always {}'"
            fzf_default_completion=expand-or-complete

            # Completion setup is invisible until it is needed. The first call
            # also registers zoxide's completion, which was defined above.
            _load_shell_completions() {
              (( ''${_shell_completions_loaded:-0} )) && return 0

              # Resolve completion paths only when completion is first used.
              # Nix profiles can contribute several symlinks to the same target.
              if [[ -z "''${IN_NIX_SHELL:-}" ]]; then
                fpath=("$HOME/.grok/completions/zsh" $fpath)
              fi
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
              # Lazy FZF initialization runs after Atuin. Keep Ctrl-R owned by
              # Atuin and leave directory navigation to zoxide.
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

            # Atuin accepts its compact 32-hex session ID. Generating it with
            # shell randomness avoids launching the CLI solely for a UUID.
            if [[ -z "''${ATUIN_SESSION:-}" || "''${ATUIN_SHLVL:-}" != "$SHLVL" ]]; then
              printf -v ATUIN_SESSION '%04x%04x%04x%04x%04x%04x%04x%04x' \
                $RANDOM $RANDOM $RANDOM $RANDOM $RANDOM $RANDOM $RANDOM $RANDOM
              export ATUIN_SESSION ATUIN_SHLVL=$SHLVL
            fi
            source ${atuinZshInit}
          fi
        '')
      ];
    };

    # Keep Bash aligned with Zsh. The flake still owns PATH inside `nix develop`;
    # Home Manager contributes the same aliases, integrations, and Starship hook.
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
          # Source static integrations generated during the Nix build.
          source ${zoxideBashInit}

          if [[ :$SHELLOPTS: =~ :(vi|emacs): ]]; then
            export FZF_CTRL_T_OPTS="--preview 'bat --style=numbers --color=always {}'"
            source ${pkgs.fzf}/share/fzf/key-bindings.bash

            # Queue a normal Tab after this one-shot Readline macro loads both
            # completion frameworks. This preserves first-Tab behavior.
            # The rebind runs on every invocation: /etc/bashrc already loads
            # bash-completion on NixOS, so BASH_COMPLETION_VERSINFO cannot be
            # used as the loaded sentinel. Without the rebind, Tab would stay
            # bound to this macro and recurse until Readline gives up.
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

            source ${pkgs.bash-preexec}/share/bash/bash-preexec.sh
            if [[ -z "''${ATUIN_SESSION:-}" || "''${ATUIN_SHLVL:-}" != "$SHLVL" ]]; then
              printf -v ATUIN_SESSION '%04x%04x%04x%04x%04x%04x%04x%04x' \
                $RANDOM $RANDOM $RANDOM $RANDOM $RANDOM $RANDOM $RANDOM $RANDOM
              export ATUIN_SESSION ATUIN_SHLVL=$SHLVL
            fi
            source ${atuinBashInit}
          fi

          if [[ $TERM != "dumb" ]]; then
            source ${starshipBashInit}
          fi
        '')
      ];
    };

    atuin = {
      enable = true;
      package = unstablePkgs.atuin;
      # Static, build-time-generated integrations are sourced above.
      enableBashIntegration = false;
      enableZshIntegration = false;

      # Keep Atuin's generated config fully declarative.
      forceOverwriteSettings = true;

      settings = {
        auto_sync = true;
        sync_frequency = "5m";
        search_mode = "daemon-fuzzy";

        # Give Atuin AI useful terminal context and access to its unique history
        # features, but leave filesystem mutation and command execution to the
        # dedicated coding agents.
        ai = {
          enabled = true;
          yolo = false;

          opening = {
            send_cwd = true;
            send_last_command = true;
          };

          capabilities = {
            enable_history_search = true;
            enable_history_output = true;
            enable_file_tools = false;
            enable_command_execution = false;
          };
        };

        # Ctrl-R searches globally; up-arrow starts in the current directory.
        filter_mode = "global";
        filter_mode_shell_up_key_binding = "directory";
        workspaces = true;

        style = "compact";
        inline_height = 20;
        inline_height_shell_up_key_binding = 10;
        show_preview = true;
        max_preview_height = 4;

        exit_mode = "return-query";
        enter_accept = false;
        keymap_mode = "auto";
        secrets_filter = true;

        # `pass show` can print credentials and command substitutions can embed
        # secret-store paths. Keep all password-store invocations out of Atuin.
        history_filter = [ "\\bpass\\b" ];
      };

      # Home Manager manages the daemon as a launchd agent on macOS.
      daemon = {
        enable = true;
        logLevel = "warn";
      };
    };

    # Both shells source build-time-generated Starship initialization above.
    starship = {
      enable = true;
      enableZshIntegration = false;
      enableBashIntegration = false;
    };
  };
}
