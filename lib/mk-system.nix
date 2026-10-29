# Wire one host: its machine, its user's system settings, and that user's
# Home Manager configuration. Host and user settings live in those modules.
{
  self,
  nixpkgs,
  nixpkgs-unstable,
  home-manager,
  nix-darwin,
  ...
}@inputs:

{
  name,
  system,
  user,
}:

let
  inherit (nixpkgs) lib;
  hosts = import ../hosts.nix;
  isDarwin = lib.hasSuffix "-darwin" system;
  platform = if isDarwin then "darwin" else "nixos";
  systemBuilder = if isDarwin then nix-darwin.lib.darwinSystem else lib.nixosSystem;
  homeManagerModule =
    if isDarwin then
      home-manager.darwinModules.home-manager
    else
      home-manager.nixosModules.home-manager;
  unstablePkgs = import nixpkgs-unstable {
    inherit system;
    config.allowUnfree = true;
  };
in
systemBuilder {
  inherit system;
  specialArgs = { inherit hosts inputs; };

  modules = [
    ../machines/${platform}
    ../users/${user}/${platform}.nix
    homeManagerModule
    {
      nixpkgs.config.allowUnfree = true;
      system.configurationRevision = self.rev or self.dirtyRev or null;

      # Trust every other host's key so SSH between them never prompts.
      programs.ssh.knownHosts = lib.mapAttrs (_: host: {
        extraHostNames = [ host.address ];
        publicKey = host.hostKey;
      }) (removeAttrs hosts [ name ]);

      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
        extraSpecialArgs = {
          inherit
            hosts
            inputs
            isDarwin
            unstablePkgs
            ;
          configurationName = name;
          rebuildCommand = if isDarwin then "darwin-rebuild" else "nixos-rebuild";
        };
        users.${user} = ../users/${user}/home-manager.nix;
      };
    }
  ];
}
