{ inputs, pkgs, ... }:

{
  imports = [
    ./hardware.nix
    ./immich.nix
  ];

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  # Compress new writes without rewriting existing data during migration.
  fileSystems = {
    "/".options = [ "compress=zstd:1" ];
    "/home".options = [ "compress=zstd:1" ];
    "/nix".options = [ "compress=zstd:1" ];
  };

  networking = {
    hostName = "z";
    networkmanager = {
      enable = true;
      wifi.powersave = false;
    };
  };

  # Pair HID devices like the Logitech MX Keys over the onboard adapter.
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  time.timeZone = "America/Los_Angeles";

  i18n.defaultLocale = "en_US.UTF-8";

  # Keep Nix managed by NixOS while replacing only its package with the pinned
  # Determinate distribution and matching dependencies.
  nix.package = inputs.determinate-nix.packages.${pkgs.stdenv.hostPlatform.system}.default;

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];

    # Bound both simultaneous derivations and parallel workers per derivation.
    max-jobs = 2;
    cores = 4;

    # Determinate's evaluator features are not enabled by the NixOS module,
    # because NixOS owns nix.conf instead of the Determinate installer.
    eval-cores = 0;
    lazy-trees = true;

    # NixOS runs the Nix binary without Determinate's netrc-merging helper.
    # Manual: put the Rex package token here, owned by dp with mode 0600, for
    # both user-side flake downloads and root's Nix daemon. See
    # https://www.superlogical.com/rex/docs/linux/installation#nix-and-nixos
    netrc-file = "/etc/determinate/rex.netrc";
  };

  # Compress cold pages during bursts; this is capacity, not reserved RAM.
  zramSwap = {
    enable = true;
    memoryPercent = 25;
  };

  # User-facing tools are owned by Home Manager. Keep only the terminal data
  # required before the user profile is available.
  environment.systemPackages = [ pkgs.ghostty.terminfo ];

  programs = {
    atop.enable = true;

    # Prebuilt Linux binaries find these through nix-ld; T3 Code's downloaded
    # headless Chrome (its preview browser) needs this set.
    nix-ld = {
      enable = true;
      libraries = with pkgs; [
        alsa-lib
        at-spi2-atk
        at-spi2-core
        atk
        dbus
        expat
        glib
        libgbm
        libx11
        libxcb
        libxcomposite
        libxdamage
        libxext
        libxfixes
        libxkbcommon
        libxrandr
        nspr
        nss
        systemd
      ];
    };
  };

  services = {
    # Mirror the Mac's Karabiner layers on every detected keyboard.
    kanata = {
      enable = true;
      keyboards.phony.config = builtins.readFile ../../config/kanata/box.kbd;
    };

    # SSH is reachable only inside the tailnet and still requires the user's
    # declared public key.
    openssh = {
      enable = true;
      openFirewall = false;
      settings = {
        KbdInteractiveAuthentication = false;
        PasswordAuthentication = false;
        PermitRootLogin = "no";
      };
    };

    # Establish the encrypted transport first. Manual: `sudo tailscale up` and
    # the `tailscale serve` routes, so no tailnet credential enters the Nix store.
    tailscale = {
      enable = true;
      openFirewall = true;
    };
  };

  # SSH/SFTP, Tailscale Serve HTTPS, Rex, and previews (8765 static, 8766-8799
  # development apps) are private to the tailnet. Tailscale accepts tailnet
  # traffic before this firewall, so its access rules decide who reaches them.
  # Manual: z is shared with another user; in the tailnet policy, grant
  # autogroup:shared only the ports they need (such as 443), not "*".
  networking.firewall.interfaces.tailscale0 = {
    allowedTCPPorts = [
      22
      443
      7297
    ];
    allowedTCPPortRanges = [
      {
        from = 8765;
        to = 8799;
      }
    ];
  };

  # The recording service reads these separately from the interactive atoprc.
  environment.etc."default/atop".text = ''
    LOGINTERVAL=60
    LOGGENERATIONS=14
  '';

  systemd = {
    services.nix-daemon.serviceConfig = {
      MemoryHigh = "8G";
      MemoryMax = "10G";
      TasksMax = 2048;
      # Fail builds together on OOM and recover the daemon for subsequent jobs.
      OOMPolicy = "kill";
      ManagedOOMMemoryPressure = "kill";
      Restart = "on-failure";
      RestartSec = "5s";
    };

    # Builds, agents, and the UI have separate ceilings totalling 24 GiB.
    # The remaining RAM supports the OS, SSH/Tailscale, and the Immich stack.
    user = {
      slices."app-t3code".sliceConfig = {
        # T3 adjusts its child slices at runtime. Limit their parent so those
        # adjustments cannot consume the host's remaining memory budget.
        MemoryHigh = "8G";
        MemoryMax = "10G";
        TasksMax = 2048;
        ManagedOOMMemoryPressure = "kill";
      };

      units."t3code.service" = {
        # Keep the app's executable and environment; add only resource policy.
        overrideStrategy = "asDropin";
        text = ''
          [Service]
          MemoryHigh=3G
          MemoryMax=4G
          TasksMax=2048
          OOMPolicy=kill
        '';
      };
    };

    # Personal file storage is independent of the Immich deployment.
    tmpfiles.rules = [ "d /srv/data/files 0750 dp users -" ];
  };

  # Preserve the version from the machine's original installation.
  system.stateVersion = "26.05";
}
