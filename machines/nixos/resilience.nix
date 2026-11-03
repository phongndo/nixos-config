{ pkgs, ... }:

# Keep z reachable over the tailnet when hardware misbehaves. The onboard
# Qualcomm WCN7850 Wi-Fi (ath12k) firmware has wedged once, flooding the log
# for days before the host hung hard and sat dead until someone power-cycled it.
#
# Manual, in the MSI BIOS: set "Restore after AC Power Loss" to "Power On" so
# a power cut does not leave z off. Keep Ethernet plugged in; it is the
# dependable uplink and NetworkManager prefers it over Wi-Fi.
let
  # Reset the Wi-Fi card when its firmware stops answering the driver. A warm
  # reset cannot help once the card has dropped off the PCI bus; that needs
  # the PSU switched off, so the script only reports it.
  ath12kRecover = pkgs.writeShellApplication {
    name = "ath12k-recover";
    runtimeInputs = with pkgs; [
      coreutils
      gnugrep
      systemd
    ];
    text = ''
      state=/var/lib/ath12k-recover/last-reset
      cooldown=1800
      threshold=10

      dev=""
      for d in /sys/bus/pci/devices/*; do
        if [ "$(cat "$d/vendor")" = 0x17cb ] && [ "$(cat "$d/device")" = 0x1107 ]; then
          dev=$d
        fi
      done

      if [ -z "$dev" ]; then
        echo "WCN7850 Wi-Fi is not on the PCI bus; switch the PSU off for a minute to bring it back" >&2
        exit 0
      fi

      errors=$(journalctl -k --since "5 min ago" -o cat \
        | grep -cE 'ath12k_pci .*(time out while waiting for (get )?fw stats|failed to pull fw stats|firmware crashed)' \
        || true)
      iface=$(ls "$dev/net" 2>/dev/null || true)

      if [ "$errors" -lt "$threshold" ] && [ -n "$iface" ]; then
        exit 0
      fi

      now=$(date +%s)
      if [ -f "$state" ] && [ $((now - $(cat "$state"))) -lt "$cooldown" ]; then
        echo "Wi-Fi unhealthy ($errors errors, interface '$iface') but reset within the last $cooldown s; waiting" >&2
        exit 0
      fi
      echo "$now" > "$state"

      bdf=$(basename "$dev")
      echo "Resetting Wi-Fi $bdf ($errors errors in 5 min, interface '$iface')" >&2
      if [ -e "$dev/driver" ]; then
        echo "$bdf" > "$dev/driver/unbind"
      fi
      echo 1 > "$dev/remove"
      sleep 2
      echo 1 > /sys/bus/pci/rescan
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

  systemd.services.ath12k-recover = {
    description = "Reset the Wi-Fi card when its firmware wedges";
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
