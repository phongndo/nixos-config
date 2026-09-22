{ lib, isDarwin, ... }:

{
  imports = [ ../../home ] ++ lib.optionals isDarwin [ ../../home/darwin.nix ];

  home = {
    username = "dp";
    homeDirectory = if isDarwin then "/Users/dp" else "/home/dp";
  };

  programs.ssh = lib.mkIf (!isDarwin) {
    enable = true;
    enableDefaultConfig = false;
    settings.y = {
      HostName = "100.90.20.37";
      User = "dp";
      IdentityFile = "~/.ssh/id_ed25519_y";
      IdentitiesOnly = true;
    };
  };
}
