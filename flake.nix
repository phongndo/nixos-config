{
  description = "dp's personal Nix configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    determinate-nix = {
      url = "https://flakehub.com/f/DeterminateSystems/nix-src/3.23.1";
      # Match the dependency revision tested by this Determinate release.
      inputs.nixpkgs.url = "github:NixOS/nixpkgs/c5c4a43b0e8056328ec4529f735cabdb8f1942bb";
    };

    rex = {
      url = "https://pkgs.superlogical.com/rex/nix/preview.tar.gz";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, ... }@inputs:
    let
      mkSystem = import ./lib/mk-system.nix inputs;
      systems = [
        "aarch64-darwin"
        "x86_64-linux"
      ];
    in
    {
      darwinConfigurations.y = mkSystem {
        name = "y";
        system = "aarch64-darwin";
        user = "dp";
      };

      nixosConfigurations.z = mkSystem {
        name = "z";
        system = "x86_64-linux";
        user = "dp";
      };

      formatter = nixpkgs.lib.genAttrs systems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);
    };
}
