import QtQuick
import Quickshell
import Quickshell.Io

// Headless: watches for an NVIDIA GPU (built-in or a Thunderbolt/USB4
// eGPU enclosure) that isn't correctly bound to the nvidia driver --
// either because dkms didn't rebuild for the running kernel, or because
// nouveau ended up claiming (or failing to claim) the card instead -- and
// sends one notification per boot, pointing at the bundled fix script.
// Never applies the fix itself: that needs root, touches
// /etc/modprobe.d and the initramfs, and always needs a reboot to
// verify, none of which a background shell service should do unattended.
Item {
  id: root

  property var shell: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string pluginDir: home + "/.config/omarchy/plugins/nvidia-dkms-guard"
  readonly property string fixScript: pluginDir + "/bin/omarchy-nvidia-dkms-guard"
  // Boot-scoped (tmpfs, cleared automatically every boot/logout) rather than
  // ~/.local/state: these markers exist only to dedupe repeat notifications
  // within a single boot, and a marker that outlived its boot would
  // permanently suppress the notification for a real future regression.
  readonly property string stateDir: Quickshell.env("XDG_RUNTIME_DIR") + "/omarchy/indicators"
  // Separate marker per exit code, not one shared marker: a boot can
  // legitimately pass through "needs fix" (1) and, once you've run it,
  // "staged, reboot" (2) in the same session, and each transition is worth
  // its own one-time notification rather than only ever firing once total.
  readonly property string neededMarker: stateDir + "/nvidia-dkms-guard-notified-needed"
  readonly property string stagedMarker: stateDir + "/nvidia-dkms-guard-notified-staged"

  function runCheck() {
    if (checkProcess.running) return
    checkProcess.running = true
  }

  function notifyOnce(marker, title, body) {
    notifyProcess.command = ["bash", "-c",
      "mkdir -p " + JSON.stringify(root.stateDir) + "; " +
      "[[ -f " + JSON.stringify(marker) + " ]] && exit 0; " +
      "touch " + JSON.stringify(marker) + "; " +
      "omarchy-notification-send -u normal " + JSON.stringify(title) + " " + JSON.stringify(body)
    ]
    notifyProcess.running = true
  }

  Process {
    id: checkProcess
    command: ["bash", root.fixScript, "--check", "--quiet"]
    onExited: function(exitCode) {
      if (exitCode === 1) {
        root.notifyOnce(root.neededMarker,
          "NVIDIA GPU driver needs a fix",
          "An NVIDIA GPU isn't bound to the nvidia driver (dkms/kernel mismatch or nouveau in the way). Run: " + root.fixScript)
      } else if (exitCode === 2) {
        root.notifyOnce(root.stagedMarker,
          "NVIDIA GPU fix needs a reboot",
          "The dkms/blacklist fix has already been applied but isn't active yet. Reboot to finish: systemctl reboot")
      }
    }
  }

  Process {
    id: notifyProcess
  }

  Timer {
    // Shortly after shell start covers a GPU/eGPU already present at
    // login; the slow periodic timer below catches an eGPU plugged in
    // later, a kernel update landing mid-session, or a needed -> staged
    // transition after you've run the fix mid-session.
    interval: 15000
    running: true
    repeat: false
    onTriggered: root.runCheck()
  }

  Timer {
    interval: 3600000
    running: true
    repeat: true
    onTriggered: root.runCheck()
  }
}
