# omarchy-nvidia-dkms-guard

An [Omarchy](https://omarchy.org/) shell service that detects an NVIDIA GPU
— built into the machine, or living in a Thunderbolt/USB4 eGPU enclosure —
that isn't actually bound to the `nvidia` driver. Two ways that happens on
Arch/Omarchy with `nvidia-dkms`/`nvidia-open-dkms`:

- **dkms didn't rebuild for the running kernel.** After a kernel update,
  `dkms status` still shows the module built for the *previous* kernel
  version, not the one you just booted into — a silent dkms rebuild
  failure, often from `linux-headers` not being updated in lockstep.
- **nouveau is in the way.** Either `nouveau` claimed the card ahead of
  `nvidia`, or — seen on an Ampere (RTX 30-series) eGPU — nouveau tries to
  probe it and fails outright (`unable to map PRI`, `probe ... failed with
  error -12` in the kernel log), leaving the card with **no driver bound
  at all**. Both cases have the same fix: blacklist nouveau so it never
  gets a chance to claim the device, and make sure `nvidia`/`nvidia_drm`
  are what binds instead.

Neither failure is obvious from a running desktop — the screen usually
still works fine on integrated graphics, and an eGPU without a working
driver just silently sits there instead of erroring loudly; `nvidia-smi`
is the only thing that complains, and only if you think to run it.

No bar icon, no UI. It just checks periodically and sends one desktop
notification per boot if it finds a problem, pointing you at the bundled
fix script — it never touches `/etc/modprobe.d` or the initramfs itself.

## The fix

`sudo omarchy-nvidia-dkms-guard` does, only for whatever it actually
detected as broken:

1. Rebuilds the dkms module for the running kernel (`dkms install
   nvidia/<version> -k $(uname -r)`), if it was out of sync.
2. Writes `/etc/modprobe.d/blacklist-nouveau.conf` (backing up any
   existing file first), if nothing was already blacklisting nouveau.
3. Rebuilds the initramfs/UKI — via
   `/usr/share/libalpm/scripts/limine-mkinitcpio-install` on a Limine
   system (Omarchy's default; this is the same script Omarchy's own
   `90-mkinitcpio-install.hook` calls automatically after a package
   change, but a hand-written modprobe.d file isn't a tracked hook
   target, so it needs to be triggered by hand here), falling back to
   plain `mkinitcpio -P` otherwise.

It always needs a reboot afterward — a module already loaded and (not)
bound in the running session can't be swapped out live, and this script
deliberately doesn't try (rmmod/modprobe games on a live NVIDIA module are
a good way to wedge a session; a reboot is more reliable).

## Install

```
omarchy plugin add https://github.com/Thomster/omarchy-nvidia-dkms-guard.git
```

## Usage

Once installed and enabled, it runs in the background and, if it detects
a problem, sends a notification telling you to run:

```
sudo ~/.config/omarchy/plugins/nvidia-dkms-guard/bin/omarchy-nvidia-dkms-guard
```

You can also run the read-only check yourself any time, without root:

```
~/.config/omarchy/plugins/nvidia-dkms-guard/bin/omarchy-nvidia-dkms-guard --check
```

Exit codes: `0` = no NVIDIA GPU present, or it's correctly bound and dkms
matches the running kernel. `1` = a fix is needed and hasn't been applied
yet. `2` = the fix is already staged (dkms current, blacklist in place)
but the running session hasn't rebooted since — just reboot, don't re-run
the fix.

After rebooting, verify with:

```
dkms status
lspci -k | grep -A3 NVIDIA   # should say "Kernel driver in use: nvidia"
nvidia-smi
```

## Requirements

- `dkms`, and `nvidia-dkms` or `nvidia-open-dkms` installed
- `linux-headers` matching the running kernel
- Limine (Omarchy's default) or a system where plain `mkinitcpio -P`
  rebuilds your initramfs; other bootloaders aren't handled automatically
  yet — the script will tell you if it can't find a way to rebuild

## Related

Pairs with [`omarchy-thunderbolt-pcie-fix`](https://github.com/Thomster/omarchy-thunderbolt-pcie-fix)
if your NVIDIA GPU lives in a Thunderbolt/USB4 eGPU enclosure and the
dock itself also has PCIe issues (missing USB/Ethernet behind the dock) —
that one's a firmware BAR-allocation bug, this one's a driver-binding
bug; they're unrelated but tend to show up on the same kind of hardware.

## How this came to be

This is a personal customization for my own Omarchy setup, built with the
help of [Claude Code](https://claude.com/claude-code) (Anthropic's AI coding
agent) after installing `nvidia-open-dkms` for an ASUS ROG XG Station 2 eGPU
enclosure (RTX 3060) and hitting exactly the "nouveau still has it" problem
this fixes. I'm not a professional plugin developer or a kernel/driver
engineer — please read through the source before installing, especially
since it edits `/etc/modprobe.d` and rebuilds your initramfs, and open an
issue if something looks off on your hardware.

## License

MIT
