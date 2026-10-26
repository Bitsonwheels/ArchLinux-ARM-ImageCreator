# Arch Linux ARM Images

Unofficial prebuilt Arch Linux ARM images for several architectures and flavors, primarily intended for use on Raspberry Pis, including some conveniences such as

- Automatic file system expansion on first boot
- Preinstallation of `linux-rpi` and `raspberrypi-bootloader`
- Optional preinstallation of `avahi` (mDNS/DNS-SD) and other tools
- Optional preinstallation of `YAY` Yet another Yogurt - An AUR Helper written in Go


These scripts are based on the fantastic work by [andrewboring](https://github.com/andrewboring/alarm-images) and [disconnected.systems](https://disconnected.systems/blog/custom-rpi-image-with-github-travis/#first-stage-script-create-image) on making Arch Linux ARM builds in CI.

## Requirements

- Linux (full build) - or macOS with Docker (see below)
- `bash`, root privileges (or `sudo ./create-image.sh ...`)
- Tools on Linux: `losetup`, `parted`, `mkfs.vfat` (dosfstools), `mkfs.ext4` (e2fsprogs), `curl`, `tar`, `rsync` - `arch-chroot` is bundled with the repo, no need for the `arch-install-scripts` package
- On macOS/Homebrew: `parted dosfstools e2fsprogs` (partial native build) or Docker (full build)

## Usage

```
./create-image.sh <size> <arch> [setup scripts...]
```

| Argument | Example | Meaning |
| --- | --- | --- |
| `<size>` | `4G`, `8G` | Image file size |
| `<arch>` | `armv7`, `rpi-armv7`, `rpi-aarch64`, `aarch64` | Arch Linux ARM tarball / image flavor |
| `[setup scripts...]` | `setup/rpi-armv7 setup/avahi` | Optional scripts run inside the image (chroot) |

### Available architectures (`<arch>`)

`<arch>` selects the tarball `ArchLinuxARM-<arch>-latest.tar.gz` from
[archlinuxarm.org](https://archlinuxarm.org/about/downloads). Anything
listed there works. Common values:

| `<arch>` | Platform |
| --- | --- |
| `rpi` | Raspberry Pi 1 / Zero (ARMv6) |
| `rpi-2` | Raspberry Pi 2 (32-bit ARMv7) |
| `rpi-3` | Raspberry Pi 3 (aarch64 kernel) |
| `rpi-4` | Raspberry Pi 4 (aarch64 kernel) |
| `rpi-armv7` | Raspberry Pi 2/3/4 (32-bit ARMv7 userland) - used in this project's CI |
| `rpi-aarch64` | Raspberry Pi 3/4 (64-bit kernel + userland) - used in this project's CI |
| `aarch64` | Generic 64-bit ARM platform - used in this project's CI |

Examples:

```sh
sudo ./create-image.sh 8G rpi-armv7
sudo ./create-image.sh 8G rpi-aarch64 setup/rpi-aarch64 setup/avahi
```

Notes:

- The tarball is downloaded once and reused; a partial or interrupted
  download is automatically resumed (`curl -C -`).
- **The full package set (`vim`, `gcc`, `go`, `cmake`, ...) needs more than
  4 GB.** Use `8G` or larger, especially for `rpi-*` flavors with their
  additional kernel/firmware packages.

## Building on macOS

`create-image.sh` relies on Linux facilities that macOS does not provide
(`losetup`, ext4 mounts, and running ARM/Linux binaries via `arch-chroot`).
Two things make macOS builds work:

### 1. Docker wrapper (recommended, full build)

`./create-image-docker.sh` runs the exact same pipeline inside a privileged
Arch Linux container with QEMU ARM emulation:

```sh
./create-image-docker.sh 8G rpi-armv7 setup/rpi-armv7
```

It accepts the same arguments as `./create-image.sh`. Requirements:

- Docker (Desktop, Colima, OrbStack, ...) running - the first run pulls
  `archlinux` and `multiarch/qemu-user-static` and builds a small builder
  image (`archlinux-arm-image-builder`)
- Internet access (mirror downloads)

The resulting `.img` file appears in the project directory. Use
`./create-image-docker.sh --rebuild ...` to force a rebuild of the builder
image.

The build runs in a detached container (`arch-image-build`). It survives the
wrapper script being killed (shell crash, SIGTERM, ...). To watch or clean up
a running build manually:

```sh
docker logs -f arch-image-build
docker stop arch-image-build && docker rm arch-image-build
```

### 2. Native partial build (macOS, not recommended)

`create-image.sh` detects the host OS. On macOS it can create, partition and
format the image using Homebrew tools

```sh
brew install parted dosfstools e2fsprogs
./create-image.sh 8G rpi-armv7
```

but stops before the ext4 mount / chroot steps, which macOS cannot perform.
Use the Docker wrapper for complete images.

## Troubleshooting

| Symptom | Cause / Fix |
| --- | --- |
| `losetup: command not found` (macOS) | macOS has no `losetup`. Use `./create-image-docker.sh` or the native partial path (hdiutil-based). |
| `error: Partition / too full` / `not enough free disk space` | Image too small. Use `8G` or larger. |
| `error: restricting filesystem access failed because Landlock is not supported` | pacman sandbox inside containers. `create-image-docker.sh` disables it automatically (`BUILD_IN_CONTAINER=1`). |
| `chroot: failed to run command '/bin/bash': Exec format error` | ARM binaries cannot run natively on an x86_64 host. Register QEMU emulation: `docker run --rm --privileged multiarch/qemu-user-static --reset -p yes`, or install `qemu-user-static` and `systemctl restart systemd-binfmt`, or build via `./create-image-docker.sh`. The script checks this early and tells you. |
| `failed to commit transaction (download library error)` / `failed retrieving file ... Connection timed out` | Transient mirror/network failure during `pacman -Syu`. The build now retried up to 3 times (plus curl-level retries per package); if it still fails, just re-run the build - downloads resume and the tarball is cached. |
| `Error: Docker engine is not running` | Start Docker Desktop / `colima start`, then retry. |

## How it works

1. Download the Arch Linux ARM rootfs tarball (resumable).
2. Create a sparse image file, attach it as a block device
   (`losetup` on Linux, `hdiutil attach -nomount` on macOS, or device-mapper
   `kpartx` mappings inside containers).
3. Partition (FAT32 boot + ext4 root), format, mount.
4. Extract the rootfs, copy the `overlay/` tree, init the pacman keyring,
   pick the fastest mirror, install packages, configure locale, enable the
   `expand-rootfs` service, create the `alarm` user and run any setup
   scripts, then clean the pacman cache.

## Changelog

### 2026-10-26

- **Renamed** `create-image` to `create-image.sh`; all callers (CI workflow,
  Docker wrapper, docs) updated.
- **Colored output** with a consistent scheme in `create-image.sh` and
  `create-image-docker.sh`: info = magenta, warning = yellow, error = red,
  success = green. The banner/header now prints before the early macOS
  tool check, so it shows on every run.
- **Header comment** for `create-image.sh` describing purpose, usage and the
  macOS/Docker split.
- **Robust package installer**: mirror download timeouts no longer kill the
  build. Every pacman download gets curl-level retries (`XferCommand` with
  `--retry 4 --retry-delay 5`, resumable), and the whole `pacman -Syu`
  transaction is retried up to 3 times before failing with a clear hint to
  re-run (downloads resume, nothing is lost).
- **Fail-early checks** before any download starts:
  - missing native tools on Linux (`losetup`, `parted`, `mkfs.vfat`,
    `mkfs.ext4`, `curl`, `tar`, `rsync`) with distro-specific install hints
  - missing QEMU user-mode emulation (`binfmt_misc`) on x86_64 hosts,
    which previously surfaced as the cryptic
    `chroot: failed to run command '/bin/bash': Exec format error`
    mid-build
- **Bundled `arch-chroot` is now used** from the repo (script directory on
  `PATH`); the host package `arch-install-scripts` is no longer required.
  The `sudo arch-chroot` call was dropped (`sudo` resets `PATH` and would
  not find the bundled script).
- **README**: available architectures table (usage `<arch>` values),
  troubleshooting entries for the `Exec format error` and mirror timeouts.
