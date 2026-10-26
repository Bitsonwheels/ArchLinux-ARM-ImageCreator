# Builder image for ./create-image-docker.sh
#
# Provides a Linux environment with everything ./create-image.sh needs:
#   - loop devices + mount        (util-linux, requires --privileged)
#   - partitioning                (parted)
#   - filesystem tools            (dosfstools, e2fsprogs)
#   - transfer/archive            (curl, tar, rsync)
#   - chroot of ARM/Linux root    (arch-install-scripts)
#
# The ARM binaries inside the chroot (pacman-key, pacman -Syu, systemctl, ...)
# are executed via QEMU user-mode emulation, which ./create-image-docker.sh
# registers on the Docker VM using multiarch/qemu-user-static (binfmt_misc).

FROM archlinux:latest

RUN pacman -Syu --noconfirm \
        arch-install-scripts \
        curl \
        dosfstools \
        e2fsprogs \
        multipath-tools \
        parted \
        rsync \
        sudo \
        tar \
        zip \
    && sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen \
    && locale-gen \
    && pacman -Scc --noconfirm
