{
  config,
  lib,
  pkgs,
  ...
}:

let
  home = config.home.homeDirectory;

  atuinDaemon = pkgs.writeShellScript "atuin-daemon-start" ''
    # An unclean shutdown can leave these generated files behind even though
    # no daemon owns the socket. launchd guarantees this script has one active
    # instance, so they are stale whenever it starts us.
    rm -f "${config.xdg.dataHome}/atuin/daemon.sock" \
      "${config.xdg.dataHome}/atuin/atuin-daemon.pid"
    exec ${lib.getExe config.programs.atuin.package} daemon start
  '';

  agent = name: {
    enable = true;

    # Home Manager wraps the command with wait4path so launchd cannot race the
    # encrypted Nix store during login.
    config = {
      Label = "com.dp.${name}";
      ProgramArguments = [
        "/bin/sh"
        "-c"
        ''mkdir -p "${home}/.cache/${name}"; exec "${home}/.config/launchd/${name}-runner" >>"${home}/.cache/${name}/${name}.out.log" 2>>"${home}/.cache/${name}/${name}.err.log"''
      ];
      ProcessType = "Interactive";
      RunAtLoad = true;
      KeepAlive.SuccessfulExit = false;
      ThrottleInterval = 10;
    };
  };
in
{
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    settings = {
      "github.com" = {
        IdentityFile = "~/.ssh/id_ed25519";
        AddKeysToAgent = "yes";
        UseKeychain = "yes";
      };

      z = {
        HostName = "100.122.138.125";
        User = "dp";
        IdentityFile = "~/.ssh/id_ed25519";
        IdentitiesOnly = true;
        AddKeysToAgent = "yes";
        UseKeychain = "yes";
      };
    };
  };

  programs.browserpass = {
    enable = true;
    browsers = [ "chrome" ];
  };

  home.packages = with pkgs; [
    browserpass
    pass
    pinentry_mac
    skhd
    yabai
  ];

  launchd.agents = {
    # Home Manager's Atuin module owns the rest of this agent. Override only
    # its executable so stale crash state cannot create a restart loop.
    atuin-daemon.config.ProgramArguments = lib.mkForce [ "${atuinDaemon}" ];

    yabai = agent "yabai";
    skhd = agent "skhd";
  };
}
