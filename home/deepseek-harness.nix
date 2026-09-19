{
  config,
  lib,
  pkgs,
  ...
}:

let
  home = config.home.homeDirectory;
  # The service uses existing mise installations, but never resolves "latest" or
  # installs packages at boot. Update these versions only after a restart test.
  installs = "${home}/.local/share/mise/installs";
  node = "${installs}/node/26.8.1/bin/node";
  dsh = "${installs}/npm-deepseek-ai-dsh/0.1.5-rc.1/lib/node_modules/@deepseek-ai/dsh/lib/bin.js";
  authority = "z.tail5606b4.ts.net:8443";
  remoteSettings = import ../lib/dsh-remote-settings.nix {
    inherit pkgs;
    trustedOrigin = "https://${authority}";
  };
  # Service-only provider selection and remote-settings compatibility.
  # Authentication, API trust, and loopback classification elsewhere remain
  # owned by the upstream packages; saved model selections still take priority.
  webPatch = pkgs.writeText "deepseek-harness-web.cordis.patch.yml" ''
    - id: llm-deepseek
      disabled: true
    - id: agent-default-model
      config:
        provider: codex-local
        model: gpt-6-astra
    - id: ui-settings
      disabled: true
    - insert:
        - id: ui-settings-remote
          name: ${remoteSettings}/lib/index.js
  '';
  login = pkgs.writeShellScript "dsh-web-login" ''
    export PATH=${lib.makeBinPath [ pkgs.systemd ]}:"$PATH"
    exec ${pkgs.python3}/bin/python3 ${../bin/dsh-web-login.py} \
      --authority ${lib.escapeShellArg authority} "$@"
  '';
in
{
  # This shared home tree also serves the Mac; only the Linux box hosts the UI.
  config = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    home.file.".local/bin/dsh-web-login".source = login;

    systemd.user = {
      startServices = "sd-switch";
      services.deepseek-harness = {
        Unit = {
          Description = "DeepSeek Harness private web UI";
          # Retry even if a first activation races installation of the runtime.
          StartLimitIntervalSec = 0;
        };
        Service = {
          Type = "simple";
          WorkingDirectory = "${home}/code";
          ExecStart = "${node} ${dsh} web --patch ${webPatch} --host 127.0.0.1 --port 8787 --no-open --trusted-host ${authority}";
          Environment = [
            "HOME=${home}"
            "DSH_HOME=${home}/.dsh"
            "DSH_TELEMETRY_MODE=DISABLED"
            "PATH=${installs}/node/26.8.1/bin:${installs}/pnpm/12.4.1:${home}/.local/bin:/etc/profiles/per-user/${config.home.username}/bin:${home}/.nix-profile/bin:/run/current-system/sw/bin"
          ];
          Restart = "on-failure";
          RestartSec = 10;
          TimeoutStopSec = 30;
          KillMode = "control-group";
          UMask = "0077";
        };
        Install.WantedBy = [ "default.target" ];
      };
    };
  };
}
