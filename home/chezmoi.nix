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

    # Set this before mise parses configuration, not inside its TOML template.
    sessionVariables.MISE_IGNORED_CONFIG_PATHS = "${source}/dot_config/mise/config.toml.tmpl";

    activation = {
      # Link the bootstrap config before applying agent files and mise plugins.
      # Activation's PATH has no Python, which Zed's modify script runs on.
      chezmoiApply = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        PATH="${lib.makeBinPath [ pkgs.python3 ]}:$PATH" $DRY_RUN_CMD ${lib.getExe pkgs.chezmoi} apply \
          --source "${source}" \
          --destination "${config.home.homeDirectory}" \
          --force \
          --no-tty
      '';

      # Install the tools selected by the freshly applied mise configuration.
      miseInstall = lib.hm.dag.entryAfter [ "chezmoiApply" ] ''
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
