{
  config,
  lib,
  pkgs,
  unstablePkgs,
  ...
}:

let
  source = "${config.home.homeDirectory}/nix-config/chezmoi";
in
{
  # This is the only bridge from Home Manager to the live agent-tool tree.
  # Agent files are not part of a Nix generation and do not roll back with it.
  home = {
    packages = [
      pkgs.chezmoi
      unstablePkgs.mise
    ];

    # Activation starts with a restricted PATH, not home.packages or mise.
    # The run_after skill-sync hook needs both Python and Git before miseInstall.
    extraActivationPath = [
      pkgs.python3
      pkgs.git
    ];

    # Set this before mise parses configuration, not inside its TOML template.
    sessionVariables.MISE_IGNORED_CONFIG_PATHS = "${source}/dot_config/mise/config.toml.tmpl";

    activation = {
      # Link the bootstrap config before applying agent files and mise plugins.
      chezmoiApply = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        $DRY_RUN_CMD ${lib.getExe pkgs.chezmoi} apply \
          --source "${source}" \
          --destination "${config.home.homeDirectory}" \
          --force \
          --no-tty
      '';

      # Install pinned service runtimes before systemd reloads/starts user units.
      miseInstall = lib.hm.dag.entryBetween [ "reloadSystemd" ] [ "chezmoiApply" ] ''
        $DRY_RUN_CMD ${lib.getExe unstablePkgs.mise} --yes -C "${config.home.homeDirectory}" install
      '';
    };
  };

  xdg.configFile."chezmoi/chezmoi.toml" = {
    text = ''
      sourceDir = "${source}"
    '';
    force = true;
  };
}
