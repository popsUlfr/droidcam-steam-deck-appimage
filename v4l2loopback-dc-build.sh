#!/bin/bash
set -eux
# podman pull archlinux:latest
# podman run -v ./:/tmp/out --rm -ti archlinux:latest /tmp/out/v4l2loopback-dc-build.sh
# archlinux image
OUT_DIR="/tmp/out"
TMP_PKG_DIR="/tmp/v4l2loopback-dc"
# Add SteamOS server and repos
echo 'Server = https://steamdeck-packages.steamos.cloud/archlinux-mirror/$repo/os/$arch' > /etc/pacman.d/mirrorlist
sed -i -e 's/\s*#\?\s*SigLevel\s*=\s*.*$/SigLevel = Never/g' -e 's#^\(\[core\]\)#[jupiter]\nInclude = /etc/pacman.d/mirrorlist\n\n[holo]\nInclude = /etc/pacman.d/mirrorlist\n\n\1#' /etc/pacman.conf
# Reinstall all packages
pacman -Syy
yes | pacman -S --overwrite='*' $(pacman -Qqn)
pacman -S --noconfirm --needed base-devel git sudo
useradd -m builduser
echo 'builduser ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/builduser
su -l -c 'git clone https://aur.archlinux.org/droidcam.git && cd droidcam && makepkg -si --noconfirm' builduser
mkdir -p "$TMP_PKG_DIR"
tar -xf "$OUT_DIR/v4l2loopback-dc.tar" -C "$TMP_PKG_DIR"
tar -cf - /etc/modules-load.d /etc/modprobe.d | tar -xf - -C "$TMP_PKG_DIR"
for repo in jupiter jupiter-beta jupiter-main
do
    ret_code="$(curl -sSLIo /dev/null -w '%{http_code}' "https://steamdeck-packages.steamos.cloud/archlinux-mirror/${repo}/os/x86_64/${repo}.db")"
    if [[ "$ret_code" == '200' ]]
    then
        sed -i 's/^\[jupiter[^]]*\]/['"$repo"']/' /etc/pacman.conf
        pacman -Sy --noconfirm linux-neptune linux-neptune-headers
        kf="$(pacman -Qlq linux-neptune | grep '/usr/lib/modules/[^/]\+/' | head -n 1)"
        dkms_src="$(basename /usr/src/v4l2loopback-dc*)"
        dkms install "${dkms_src%-*}/${dkms_src##*-}" -k "$(basename "$kf")"
        tar -cf - "${kf}updates/dkms" | tar -xf - -C "$TMP_PKG_DIR"
    fi
done
tar -cf "$OUT_DIR/v4l2loopback-dc.tar" -C "$TMP_PKG_DIR" .
