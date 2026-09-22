{
  self,
  nixpkgs,
  nixpkgs-unstable,
  llm-agents,
  home-manager,
  nix-darwin,
}:

{
  name,
  system,
  user,
  modules ? [ ],
}:

let
  isDarwin = nixpkgs.lib.hasSuffix "-darwin" system;
  platform = if isDarwin then "darwin" else "nixos";
  systemBuilder = if isDarwin then nix-darwin.lib.darwinSystem else nixpkgs.lib.nixosSystem;
  machineConfig = ../machines + "/${platform}";
  userSystemConfig = ../users + "/${user}/${platform}.nix";
  userHomeConfig = ../users + "/${user}/home-manager.nix";
  homeManagerModule =
    if isDarwin then
      home-manager.darwinModules.home-manager
    else
      home-manager.nixosModules.home-manager;
  rebuildCommand = if isDarwin then "darwin-rebuild" else "nixos-rebuild";
  unstablePkgs = import nixpkgs-unstable {
    inherit system;
    config.allowUnfree = true;
  };
in
systemBuilder {
  inherit system;

  modules = [
    machineConfig
    userSystemConfig

    {
      nixpkgs.config.allowUnfree = true;
      system.configurationRevision = self.rev or self.dirtyRev or null;
    }
    homeManagerModule
    {
      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
        extraSpecialArgs = {
          configurationName = name;
          cliProxyPackage = llm-agents.packages.${system}.cli-proxy-api;
          inherit isDarwin rebuildCommand unstablePkgs;
        };
        users.${user} = import userHomeConfig;
      };
    }
  ]
  ++ modules;
}
