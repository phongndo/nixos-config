{
  description = "dp's personal Nix configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    # Personal tools can advance without moving either host's system packages.
    nixpkgs-personal.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    determinate-nix = {
      url = "https://flakehub.com/f/DeterminateSystems/nix-src/3.23.1";
      # Match the dependency revision tested by this Determinate release.
      inputs.nixpkgs.url = "github:NixOS/nixpkgs/c5c4a43b0e8056328ec4529f735cabdb8f1942bb";
    };

    rex = {
      url = "https://pkgs.superlogical.com/rex/nix/preview.tar.gz";
      inputs.nixpkgs.follows = "nixpkgs-personal";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs-personal";
    };

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-personal,
      nixpkgs-unstable,
      home-manager,
      nix-darwin,
      ...
    }@inputs:
    let
      inherit (nixpkgs) lib;
      hosts = import ./hosts.nix;
      specialArgs = { inherit hosts inputs; };
      systems = [
        "aarch64-darwin"
        "x86_64-linux"
      ];

      shared =
        homeModule:
        { config, pkgs, ... }:
        {
          nixpkgs.config.allowUnfree = true;
          system.configurationRevision = self.rev or self.dirtyRev or null;

          # Trust the other host by name and tailnet address.
          programs.ssh.knownHosts = lib.mapAttrs (_: host: {
            extraHostNames = [ host.address ];
            publicKey = host.hostKey;
          }) (removeAttrs hosts [ config.networking.hostName ]);

          home-manager = {
            useUserPackages = true;
            extraSpecialArgs = {
              inherit hosts inputs;
              unstablePkgs = import nixpkgs-unstable {
                inherit (pkgs.stdenv.hostPlatform) system;
                config.allowUnfree = true;
              };
            };
            users.dp = {
              imports = [
                ./home
                homeModule
              ];
              # Pin Home Manager's packages independently of the host packages.
              _module.args.pkgsPath = nixpkgs-personal.outPath;
              nixpkgs.config.allowUnfree = true;
            };
          };
        };
    in
    {
      darwinConfigurations.y = nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        inherit specialArgs;
        modules = [
          ./machines/darwin
          ./users/dp/darwin.nix
          home-manager.darwinModules.home-manager
          (shared ./home/darwin.nix)
        ];
      };

      nixosConfigurations.z = lib.nixosSystem {
        system = "x86_64-linux";
        inherit specialArgs;
        modules = [
          ./machines/nixos
          ./users/dp/nixos.nix
          home-manager.nixosModules.home-manager
          (shared ./home/linux.nix)
        ];
      };

      formatter = lib.genAttrs systems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);
    };
}
