#!/bin/bash
#
# create-image-docker.sh - build an Arch Linux ARM image on macOS (or any
# host with Docker) inside a privileged Arch Linux container.
#
# Why: ./create-image needs Linux facilities that macOS does not provide
# (losetup, ext4 mounts, arch-chroot of ARM/Linux binaries). Running the
# exact same script inside an Arch Linux container gives macOS users a fully
# working build without changing the pipeline itself.
#
# Usage: identical to ./create-image:
#   ./create-image-docker.sh <size> <arch> [setup scripts...]
#
# Examples:
#   ./create-image-docker.sh 4G rpi-armv7
#   ./create-image-docker.sh 4G rpi-aarch64 setup/rpi-aarch64 setup/avahi
#
# Options:
#   --rebuild   Force rebuilding the builder image
#   -h, --help  Show this help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

IMAGE_NAME="archlinux-arm-image-builder"
DOCKERFILE_DIR="docker/arch-build"

usage() {
  cat <<'EOF'
Usage: ./create-image-docker.sh <size> <arch> [setup scripts...]

Builds an Arch Linux ARM image inside a privileged Arch Linux container, so
the whole pipeline (losetup, mount, arch-chroot with QEMU ARM emulation)
works on macOS too.

Options:
  --rebuild   Force rebuilding the builder image
  -h, --help  Show this help

Examples:
  ./create-image-docker.sh 4G rpi-armv7
  ./create-image-docker.sh 4G rpi-aarch64 setup/rpi-aarch64 setup/avahi
EOF
}

# Parse leading options; everything from the first positional argument on is
# passed through to ./create-image.
REBUILD=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --rebuild) REBUILD=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) break ;;
  esac
done

if [[ $# -lt 2 ]]; then
  usage
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "Error: 'docker' not found. Install Docker Desktop:" >&2
  echo "  https://www.docker.com/products/docker-desktop/" >&2
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "Error: Docker engine is not running. Start Docker Desktop and try again." >&2
  exit 1
fi

# 1) Register QEMU user-mode emulation (binfmt_misc) on the Docker VM.
#    This is what lets the ARM binaries inside the chroot (pacman-key,
#    pacman -Syu, systemctl, ...) run on an x86_64/arm64 Mac.
echo "==> Registering QEMU binfmt for ARM emulation..."
docker run --rm --privileged multiarch/qemu-user-static --reset -p yes

# 2) Build (or reuse) the builder image.
if [[ "${REBUILD}" == "1" ]] || ! docker image inspect "${IMAGE_NAME}" >/dev/null 2>&1; then
  echo "==> Building builder image ${IMAGE_NAME}..."
  docker build -t "${IMAGE_NAME}" "${DOCKERFILE_DIR}"
fi

# 3) Run the real build inside a detached container.
#    --privileged is required for losetup + mount inside the container.
#    The project directory is mounted read-write, so the resulting .img
#    lands in the working directory on the host.
#
#    The container is created, started detached and then followed via logs.
#    If THIS WRAPPER is killed (SIGTERM, shell crash, laptop reboot of the
#    terminal session), the container keeps running. Inspect it with:
#      docker logs -f arch-image-build
#    and clean up with:
#      docker stop arch-image-build && docker rm arch-image-build
CONTAINER_NAME="arch-image-build"

# Remove a leftover container from an earlier run whose wrapper was killed.
if docker ps -a --format '{{.Names}}' | grep -qx "${CONTAINER_NAME}"; then
  echo "==> Removing leftover container ${CONTAINER_NAME}..."
  docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
fi

echo "==> Creating build container ${CONTAINER_NAME}..."
docker create \
  --name "${CONTAINER_NAME}" \
  --privileged \
  -v "${SCRIPT_DIR}:/work" \
  -w /work \
  -e LANG=en_US.UTF-8 \
  -e BUILD_IN_CONTAINER=1 \
  "${IMAGE_NAME}" \
  bash -c '
    # Some Docker VMs do not ship loop devices (/dev/loop-control).
    if [ ! -e /dev/loop-control ]; then
      mknod /dev/loop-control c 10 237 2>/dev/null || true
      for i in $(seq 0 15); do
        [ -e "/dev/loop${i}" ] || mknod "/dev/loop${i}" b 7 "${i}" 2>/dev/null || true
      done
    fi
    exec ./create-image "$@"
  ' _ "$@"

echo "==> Starting build in Arch Linux container (${CONTAINER_NAME})."
echo "    The container runs detached; it survives this wrapper being killed."
docker start "${CONTAINER_NAME}" >/dev/null

# Follow the build logs. If this wrapper is terminated, the container keeps
# running - check progress with `docker logs -f arch-image-build`.
set +e
docker logs -f "${CONTAINER_NAME}"
# `docker wait` prints the container's exit code on stdout (its own exit
# status is always 0), so capture the printed value to propagate it.
rc="$(docker wait "${CONTAINER_NAME}")"
rc="${rc:-1}"
set -e
docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
exit "${rc}"
