{ isDarwin, ... }:

{
  imports = [
    ../../home
    (if isDarwin then ../../home/darwin.nix else ../../home/linux.nix)
  ];

  home = {
    username = "dp";
    homeDirectory = if isDarwin then "/Users/dp" else "/home/dp";
  };
}
