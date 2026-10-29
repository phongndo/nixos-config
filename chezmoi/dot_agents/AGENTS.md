y is a Mac on nix-darwin with Determinate Nix and z is NixOS, both configured in ~/nix-config; if `IN_NIX_SHELL` is set, the project's dev shell is already active, so run tools directly, otherwise use `nix develop -c <command>`; use `nix shell nixpkgs#<package> -c <command>` for one-off tools.

Project secrets live in 1Password Environments: on y, manage them with the 1Password MCP server; on z, run commands with `op run --environment <id> -- <command>`. Never print secret values.
