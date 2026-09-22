{ pkgs, ... }:

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

  i18n = {
    defaultLocale = "en_US.UTF-8";
    extraLocaleSettings = {
      LC_ADDRESS = "en_US.UTF-8";
      LC_IDENTIFICATION = "en_US.UTF-8";
      LC_MEASUREMENT = "en_US.UTF-8";
      LC_MONETARY = "en_US.UTF-8";
      LC_NAME = "en_US.UTF-8";
      LC_NUMERIC = "en_US.UTF-8";
      LC_PAPER = "en_US.UTF-8";
      LC_TELEPHONE = "en_US.UTF-8";
      LC_TIME = "en_US.UTF-8";
    };
  };

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];

    # Determinate's evaluator features are not enabled by the NixOS module,
    # because NixOS owns nix.conf instead of the Determinate installer.
    eval-cores = 0;
    lazy-trees = true;
  };

  # User-facing tools are owned by Home Manager. Keep only the terminal data
  # required before the user profile is available.
  environment.systemPackages = [ pkgs.ghostty.terminfo ];

  programs.nix-ld.enable = true;

  # Pin y's host key so unattended SSH never needs a trust-on-first-use prompt.
  programs.ssh.knownHosts.y = {
    extraHostNames = [ "100.90.20.37" ];
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPChw4RsEFgDyt/Wc9GVoLw4nztnx7us5pWwUg5EFYXu";
  };

  services = {
    xserver.xkb = {
      layout = "us";
      variant = "";
    };

    # Mirror the Mac's Karabiner layers on every detected keyboard.
    kanata = {
      enable = true;
      keyboards.phony.config = builtins.readFile ../../kanata/box.kbd;
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

    # Establish the encrypted transport first. Authentication remains an
    # explicit interactive step so no tailnet credential enters the Nix store.
    tailscale = {
      enable = true;
      openFirewall = true;
    };
  };

  # SSH/SFTP and Tailscale Serve HTTPS are private to the tailnet.
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [
    22
    443
    8443 # DeepSeek Harness; its backend remains on loopback.
  ];

  # Personal file storage is independent of the Immich deployment.
  systemd.tmpfiles.rules = [ "d /srv/data/files 0750 dp users -" ];

  # Preserve the version from the machine's original installation.
  system.stateVersion = "26.05";
}
