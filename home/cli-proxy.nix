{
  config,
  lib,
  pkgs,
  cliProxyPackage,
  ...
}:

let
  localProxy = pkgs.writeShellScriptBin "cli-proxy-local" ''
    exec ${pkgs.python3}/bin/python3 ${../bin/cli-proxy-local.py} \
      ${cliProxyPackage}/bin/cli-proxy-api "$@"
  '';
in
{
  # Chezmoi owns the non-secret template/client config. Each machine generates
  # its own private keys and OAuth state; no credentials are shared or copied.
  home.packages = [
    cliProxyPackage
    localProxy
  ];

  launchd.agents.cli-proxy-api = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
    enable = true;
    config = {
      Label = "com.dp.cli-proxy-api";
      ProgramArguments = [
        "${localProxy}/bin/cli-proxy-local"
        "serve"
      ];
      EnvironmentVariables.HOME = config.home.homeDirectory;
      RunAtLoad = true;
      KeepAlive.SuccessfulExit = false;
      ThrottleInterval = 30;
      ProcessType = "Background";
    };
  };

  systemd.user = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    startServices = "sd-switch";
    services.cli-proxy-api = {
      Unit = {
        Description = "Local Codex account proxy";
        # A first boot can race the initial chezmoi activation; retry until its
        # non-secret template exists rather than permanently hitting a limit.
        StartLimitIntervalSec = 0;
      };
      Service = {
        ExecStart = "${localProxy}/bin/cli-proxy-local serve";
        Environment = "HOME=${config.home.homeDirectory}";
        Restart = "on-failure";
        RestartSec = 30;
        UMask = "0077";
        NoNewPrivileges = true;
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
