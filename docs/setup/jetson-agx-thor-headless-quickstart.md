# Jetson AGX Thor Headless Quick Start

This is THOR’s repo-owned runbook for bringing up a brand-new Jetson AGX Thor Developer Kit from macOS without a monitor.

It is based on NVIDIA’s current Jetson AGX Thor quick-start flow plus the internal Shenzhen bring-up notes we were already using in `trainops/JetsonThor`, but it is now kept in this public repo so THOR does not depend on private local skills.

## What THOR Assumes

- You already created a bootable Jetson ISO USB stick.
- You have a Mac with a data-capable USB cable.
- You want the first boot, OEM-config, and first SSH path to work entirely headless.

## Hardware Path

1. Plug the bootable USB stick into a Thor USB-A port.
2. Plug power into Thor USB-C `5b`.
3. Plug a USB data cable from your Mac into the Thor Debug-USB port `8`.
4. Open the UEFI serial console from macOS.

## Phase 1 — UEFI / Installer

Factory UEFI `38.0.0` is known to render badly on serial unless the terminal is sized to `242x61`.

THOR includes a helper:

```bash
Scripts/jetson-thor/thor_serial.sh uefi
```

This auto-picks the second `/dev/cu.usbserial-*` device, sends the resize escape sequence, and opens either `tio` or `screen` at `9600` baud.

From there:

1. Boot the board.
2. Let it boot from the USB installer.
3. Choose `Flash Jetson Thor AGX Developer Kit on NVMe`.
4. Wait for the BSP install to finish.
5. Let the automatic UEFI update run.
6. Remove the USB stick after the second reboot so it does not loop back into the installer.

## Phase 2 — OEM-config CUI

After the NVMe boot starts, move the USB cable from Debug-USB `8` to USB-C `5a`.

THOR helper:

```bash
Scripts/jetson-thor/thor_serial.sh oem-config
```

That opens the first `/dev/cu.usbmodem*` device at `115200` baud.

Walk through:

1. License / locale
2. Username and password
3. Network interface selection
4. Hostname

## Phase 3 — First SSH over USB Tether

Once Jetson Linux is up, the same USB-C cable exposes a USB-Ethernet gadget.

- Thor: `192.168.55.1`
- Mac: `192.168.55.100` via a new `enX` interface

First SSH:

```bash
ssh <your-user>@192.168.55.1
```

If the tether does not appear, verify the cable is still in Thor USB-C `5a` and that macOS brought up the gadget interface.

## Phase 4 — Bootstrap SSH + Sudo

THOR now vendors a safe bootstrap helper:

```bash
Scripts/jetson-thor/bootstrap_ssh.sh <user@host> [public-key-path]
```

Example:

```bash
Scripts/jetson-thor/bootstrap_ssh.sh nvidia@192.168.55.1 ~/.ssh/id_ed25519.pub
```

This will:

1. Append your public key to `authorized_keys`
2. Enable passwordless sudo for the remote user
3. Optionally disable password auth if you set `DISABLE_PASSWORD_AUTH=1`

If THOR says no key was detected, generate one first:

```bash
ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ed25519" -C "thor-jetson"
```

## Phase 5 — JetPack / Docker Readiness

Install JetPack after the first SSH session:

```bash
ssh <your-user>@192.168.55.1 'sudo apt update && sudo apt install -y nvidia-jetpack'
```

Then verify Docker/runtime readiness:

```bash
ssh <your-user>@192.168.55.1 'docker --version && sudo systemctl status docker --no-pager'
```

After the THOR agent is installed, use THOR itself or `thorctl doctor` to verify:

```bash
thorctl doctor 8470
```

## Related THOR Surfaces

- `THOR.app` → onboarding and setup doctor now expose this same headless bring-up flow.
- `thorctl quickstart [username]` prints the same Mac-side detection and first-boot commands.

## Troubleshooting

- If the Debug-USB console does not appear, run `Scripts/jetson-thor/thor_serial.sh list` and confirm the second `/dev/cu.usbserial-*` path is present.
- If the OEM-config console does not appear, confirm the cable is on Thor USB-C `5a`, not the Debug-USB port.
- If the bootstrap helper pauses at `sudo`, stay in the terminal. THOR opens the command with a TTY so the normal password prompt can work.
- If the USB tether never appears, wait a few seconds after the CUI setup completes and check that macOS assigned a `192.168.55.x` address.

## Official NVIDIA References

- [Jetson AGX Thor Quick Start](https://docs.nvidia.com/jetson/agx-thor-devkit/user-guide/latest/quick_start.html)
- [Headless Install on UEFI 38.0.0](https://docs.nvidia.com/jetson/agx-thor-devkit/user-guide/latest/twa_headless_on_uefi-38-0-0.html)
- [Set Up JetPack](https://docs.nvidia.com/jetson/agx-thor-devkit/user-guide/latest/setup_jetpack.html)
- [Set Up Docker](https://docs.nvidia.com/jetson/agx-thor-devkit/user-guide/latest/setup_docker.html)
