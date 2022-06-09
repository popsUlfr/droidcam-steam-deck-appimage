#!/bin/bash
set -eux
# podman pull archlinux:latest
# podman run -v ./:/tmp/out --rm -ti archlinux:latest /tmp/out/v4l2loopback-dc-build.sh
# archlinux image
OUT_DIR="/tmp/out"
# Add SteamOS server and repos
echo 'Server = https://steamdeck-packages.steamos.cloud/archlinux-mirror/$repo/os/$arch' > /etc/pacman.d/mirrorlist
sed -i 's#^\(\[core\]\)#[jupiter]\nServer = https://steamdeck-packages.steamos.cloud/archlinux-mirror/$repo/os/$arch\nSigLevel = Never\n\n[holo]\nServer = https://steamdeck-packages.steamos.cloud/archlinux-mirror/$repo/os/$arch\nSigLevel = Never\n\n\1#' /etc/pacman.conf
# Reinstall all packages
pacman -Syy
pacman -Rdd --noconfirm libverto
pacman -Qqn | pacman -S --noconfirm --ignore libverto --overwrite='*' -
pacman -S --noconfirm --needed base-devel git linux-neptune linux-neptune-headers sudo
useradd -m builduser
echo 'builduser ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/builduser
su -l -c 'git clone https://aur.archlinux.org/droidcam.git && cd droidcam && makepkg -si --noconfirm' builduser
tar -rf "$OUT_DIR/v4l2loopback-dc.tar" /etc/modules-load.d /etc/modprobe.d
kf="$(pacman -Qlq linux-neptune | grep '/usr/lib/modules/[^/]\+/' | head -n 1)"
tar -rf "$OUT_DIR/v4l2loopback-dc.tar" "${kf}updates/dkms"
sed -i 's/^\[jupiter\]/\[jupiter-beta\]/' /etc/pacman.conf
pacman -Sy --noconfirm linux-neptune linux-neptune-headers
kf="$(pacman -Qlq linux-neptune | grep '/usr/lib/modules/[^/]\+/' | head -n 1)"
dkms autoinstall -k "$(basename "$kf")"
tar -rf "$OUT_DIR/v4l2loopback-dc.tar" "${kf}updates/dkms"
