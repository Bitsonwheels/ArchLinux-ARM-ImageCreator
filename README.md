# Arch Linux ARM Images

Unofficial prebuilt Arch Linux ARM images for several architectures and flavors, primarily intended for use on Raspberry Pis, including some conveniences such as

- Automatic file system expansion on first boot
- Preinstallation of `linux-rpi` and `raspberrypi-bootloader`
- Optional preinstallation of `avahi` (mDNS/DNS-SD) and other tools
- Optional preinstallation of `YAY` Yet another Yogurt - An AUR Helper written in Go


These scripts are based on the fantastic work by [andrewboring](https://github.com/andrewboring/alarm-images) and [disconnected.systems](https://disconnected.systems/blog/custom-rpi-image-with-github-travis/#first-stage-script-create-image) on making Arch Linux ARM builds in CI.

## Requirements

- Linux (full build) - or macOS with Docker (see below)
- `bash`, root privileges (or `sudo ./create-image ...`)
- Tools on Linux: `losetup`, `parted`, `mkfs.vfat` (dosfstools), `mkfs.ext4` (e2fsprogs), `curl`, `tar`, `rsync`, `arch-install-scripts` (for `arch-chroot`)
- On macOS/Homebrew: `parted dosfstools e2fsprogs` (partial native build) or Docker (full build)

## Usage

```
./create-image <size> <arch> [setup scripts...]
```

| Argument | Example | Meaning |
| --- | --- | --- |
| `<size>` | `4G`, `8G` | Image file size |
| `<arch>` | `armv7`, `rpi-armv7`, `rpi-aarch64`, `aarch64` | Arch Linux ARM tarball / image flavor |
| `[setup scripts...]` | `setup/rpi-armv7 setup/avahi` | Optional scripts run inside the image (chroot) |

Examples:

```sh
sudo ./create-image 8G rpi-armv7
sudo ./create-image 8G rpi-aarch64 setup/rpi-aarch64 setup/avahi
```

Notes:

- The tarball is downloaded once and reused; a partial or interrupted
  download is automatically resumed (`curl -C -`).
- **The full package set (`vim`, `gcc`, `go`, `cmake`, ...) needs more than
  4 GB.** Use `8G` or larger, especially for `rpi-*` flavors with their
  additional kernel/firmware packages.

## Building on macOS

`create-image` relies on Linux facilities that macOS does not provide
(`losetup`, ext4 mounts, and running ARM/Linux binaries via `arch-chroot`).
Two things make macOS builds work:

### 1. Docker wrapper (recommended, full build)

`./create-image-docker.sh` runs the exact same pipeline inside a privileged
Arch Linux container with QEMU ARM emulation:

```sh
./create-image-docker.sh 8G rpi-armv7 setup/rpi-armv7
```

It accepts the same arguments as `./create-image`. Requirements:

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

`create-image` detects the host OS. On macOS it can create, partition and
format the image using Homebrew tools

```sh
brew install parted dosfstools e2fsprogs
./create-image 8G rpi-armv7
```

but stops before the ext4 mount / chroot steps, which macOS cannot perform.
Use the Docker wrapper for complete images.

## Troubleshooting

| Symptom | Cause / Fix |
| --- | --- |
| `losetup: command not found` (macOS) | macOS has no `losetup`. Use `./create-image-docker.sh` or the native partial path (hdiutil-based). |
| `error: Partition / too full` / `not enough free disk space` | Image too small. Use `8G` or larger. |
| `error: restricting filesystem access failed because Landlock is not supported` | pacman sandbox inside containers. `create-image-docker.sh` disables it automatically (`BUILD_IN_CONTAINER=1`). |
| `failed to commit transaction (download library error)` | Transient mirror/network failure during `pacman -Syu`. Just re-run the build; downloads restart and the tarball is cached. |
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
