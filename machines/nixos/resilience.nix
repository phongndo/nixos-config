{ config, pkgs, ... }:

# Keep z reachable over the tailnet when hardware misbehaves.
#
# The onboard Qualcomm WCN7850 Wi-Fi (ath12k) firmware wedges when the eero
# switches channel or width on a DFS channel (Aug 29, Sep 25, Oct 3 2026). It
# then floods the log, and twice the chip vanished from the PCI bus across a
# reboot: the BIOS hides its slot when the chip fails link training at POST,
# and only removing power brings it back. A shutdown does not, because the chip
# sits on standby power behind its own ACPI power resource. The eero app cannot
# pin channels or avoid DFS, so the trigger stays; this module limits the damage.
#
# Wi-Fi is the fast uplink (the saved Wi-Fi connection has route metric 50);
# Ethernet goes through a slow GL.iNet and is the fallback.
#
# Manual, in the MSI BIOS: set "Restore after AC Power Loss" to "Power On" so
# a power cut does not leave z off. Keep Ethernet plugged in.
let
  # Reset the Wi-Fi chip when its firmware stops working. The reset cuts the
  # chip's power through ACPI D3cold, the same as switching the PSU off, by
  # parking the idle device on vfio-pci, which runtime-suspends it to D3cold.
  # Once the BIOS has hidden the slot nothing in software can help, so the
  # script only reports that, once per boot.
  ath12kRecover = pkgs.writeShellApplication {
    name = "ath12k-recover";
    runtimeInputs = with pkgs; [
      coreutils
      gawk
      gnugrep
      kmod
      systemd
      config.networking.networkmanager.package
    ];
    text = ''
      state=/var/lib/ath12k-recover/last-reset
      cooldown=1800
      threshold=10

      find_dev() {
        for d in /sys/bus/pci/devices/*; do
          if [ "$(cat "$d/vendor")" = 0x17cb ] && [ "$(cat "$d/device")" = 0x1107 ]; then
            echo "$d"
            return
          fi
        done
      }

      connectivity() {
        nmcli -g GENERAL.IP4-CONNECTIVITY device show "$1" 2>/dev/null | awk -F'[()]' '{print $2; exit}'
      }

      power_cycle() {
        local dev=$1 bdf control state
        bdf=$(basename "$dev")
        control=$(cat "$dev/power/control")

        if [ -e "$dev/driver" ]; then
          echo "$bdf" > "$dev/driver/unbind"
        fi
        modprobe vfio-pci
        echo vfio-pci > "$dev/driver_override"
        echo auto > "$dev/power/control"
        echo "$bdf" > /sys/bus/pci/drivers_probe

        state=unknown
        for _ in $(seq 20); do
          state=$(cat "$dev/power_state")
          [ "$state" = D3cold ] && break
          sleep 0.5
        done
        echo "Wi-Fi $bdf parked in $state" >&2
        sleep 5

        echo "$bdf" > /sys/bus/pci/drivers/vfio-pci/unbind
        echo > "$dev/driver_override"
        echo "$control" > "$dev/power/control"
        echo "$bdf" > /sys/bus/pci/drivers_probe
      }

      force=0
      if [ "''${1:-}" = --force ]; then
        force=1
      fi

      dev=$(find_dev)
      if [ -z "$dev" ]; then
        if [ ! -e /run/ath12k-recover-missing ]; then
          echo "WCN7850 Wi-Fi is not on the PCI bus; shut down and switch the PSU off for a minute to bring it back" >&2
          touch /run/ath12k-recover-missing
        fi
        exit 0
      fi

      errors=$(journalctl -k -b --since "-5min" -o cat \
        | grep -cE 'ath12k_pci .*(time out while waiting for (get )?fw stats|failed to pull fw stats|firmware crashed)' \
        || true)
      iface=$(ls "$dev/net" 2>/dev/null || true)

      # A Wi-Fi-only outage: the Wi-Fi link is up but cannot reach the
      # internet while Ethernet can, so the eero's uplink is not to blame.
      wifi_dead=0
      if [ -n "$iface" ]; then
        eth=$(nmcli -t -f DEVICE,TYPE,STATE device | awk -F: '$2 == "ethernet" && $3 == "connected" {print $1; exit}')
        if [ -n "$eth" ] \
          && nmcli -t -f DEVICE,STATE device | grep -qx "$iface:connected" \
          && [ "$(connectivity "$iface")" != full ] \
          && [ "$(connectivity "$eth")" = full ]; then
          wifi_dead=1
        fi
      fi

      if [ "$force" = 0 ] && [ "$errors" -lt "$threshold" ] && [ -n "$iface" ] && [ "$wifi_dead" = 0 ]; then
        exit 0
      fi

      now=$(date +%s)
      if [ "$force" = 0 ] && [ -f "$state" ] && [ $((now - $(cat "$state"))) -lt "$cooldown" ]; then
        echo "Wi-Fi unhealthy ($errors errors, interface '$iface', no internet: $wifi_dead) but reset within the last $cooldown s; waiting" >&2
        exit 0
      fi
      mkdir -p "$(dirname "$state")"
      echo "$now" > "$state"

      echo "Power-cycling Wi-Fi $(basename "$dev") ($errors errors in 5 min, interface '$iface', no internet: $wifi_dead, forced: $force)" >&2
      power_cycle "$dev"

      for _ in $(seq 30); do
        if [ -n "$(ls "$dev/net" 2>/dev/null)" ]; then
          echo "Wi-Fi is back as $(ls "$dev/net")" >&2
          exit 0
        fi
        sleep 1
      done
      echo "Wi-Fi did not come back within 30 s after the power cycle" >&2
      exit 1
    '';
  };
in
{
  # Reboot a hung host instead of leaving it dead. The SP5100 TCO watchdog on
  # the chipset resets the machine if systemd stops petting it for 30 s.
  systemd.settings.Manager = {
    RuntimeWatchdogSec = "30s";
    RebootWatchdogSec = "10min";
  };

  # Turn kernel lockups into panics, and reboot 10 s after a panic. The panic
  # log lands in EFI pstore and systemd-pstore saves it to
  # /var/lib/systemd/pstore on the next boot. Oopses stay non-fatal so a
  # flaky driver cannot boot-loop the host.
  boot.kernel.sysctl = {
    "kernel.panic" = 10;
    "kernel.softlockup_panic" = 1;
    "kernel.hardlockup_panic" = 1;
  };

  # Fail over to Ethernet when Wi-Fi stops reaching the internet: a device
  # whose connectivity check fails gets +20000 on its default-route metric.
  # The check binds to each device, so the reverse-path filter must be loose,
  # or the reply on the non-default device is dropped and both devices fail.
  networking.networkmanager.settings.connectivity = {
    uri = "http://nmcheck.gnome.org/check_network_status.txt";
    response = "NetworkManager is online";
    interval = 30;
  };
  networking.firewall.checkReversePath = "loose";

  environment.systemPackages = [ ath12kRecover ];

  systemd.services.ath12k-recover = {
    description = "Power-cycle the Wi-Fi chip when its firmware wedges";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${ath12kRecover}/bin/ath12k-recover";
      StateDirectory = "ath12k-recover";
    };
  };

  systemd.timers.ath12k-recover = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "1min";
    };
  };
}
