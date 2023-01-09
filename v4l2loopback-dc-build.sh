#!/bin/bash
set -eux
# podman pull archlinux:latest
# podman run -v ./:/tmp/out --rm -ti archlinux:latest /tmp/out/v4l2loopback-dc-build.sh
# archlinux image
OUT_DIR="/tmp/out"
TMP_PKG_DIR="/tmp/v4l2loopback-dc"
repo_suffixes=('' '-3.0' '-3.1' '-3.2' '-3.3' '-3.3.1' '-3.3.2' '-3.3.3' '-rel' '-beta' '-main' '-staging')
i=0
for s in "${repo_suffixes[@]}"
do
    if [[ "$s" == "${1:-}" ]]
    then
        break
    fi
    i=$((i+1))
done
ret_code="$(curl -sSLIo /dev/null -w '%{http_code}' "https://steamdeck-packages.steamos.cloud/archlinux-mirror/core${repo_suffixes[${i}]}/os/x86_64/core${repo_suffixes[${i}]}.db")"
if [[ "$ret_code" != '200' ]]
then
    exit 0
fi

# Setup builduser and module directory
useradd -m builduser
mkdir -p /etc/sudoers.d
echo 'builduser ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/builduser
mkdir -p "$TMP_PKG_DIR"
tar -xf "$OUT_DIR/v4l2loopback-dc.tar" -C "$TMP_PKG_DIR"

# Add SteamOS server and repos
echo 'Server = https://steamdeck-packages.steamos.cloud/archlinux-mirror/$repo/os/$arch' > /etc/pacman.d/mirrorlist
sed -i -e 's/\s*#\?\s*SigLevel\s*=\s*.*$/SigLevel = Never/g' -e 's#^\(\[core\]\)#[jupiter]\nInclude = /etc/pacman.d/mirrorlist\n\n[holo]\nInclude = /etc/pacman.d/mirrorlist\n\n\1#' /etc/pacman.conf
readarray -t repos < <(sed -n 's/^\[\([^]]\+\)\]/\1/p' /etc/pacman.conf | grep -v '^options$')

# core repo needs to match jupiter repo to avoid gcc mismatches
for repo in "${repos[@]}"
do
    for repo_suffix in "${repo_suffixes[@]:${i}}"
    do
        ret_code="$(curl -sSLIo /dev/null -w '%{http_code}' "https://steamdeck-packages.steamos.cloud/archlinux-mirror/${repo}${repo_suffix}/os/x86_64/${repo}${repo_suffix}.db")"
        if [[ "$ret_code" == '200' ]]
        then
            sed -i -e 's/^\['"$repo"'[^]]*\]/['"${repo}${repo_suffix}"']/g' /etc/pacman.conf
            break
        fi
    done
done
pacman -Syy
pacman -S --overwrite='*' $(pacman -Qqn) < <(yes y)
pacman -S --noconfirm --needed base-devel git sudo
pacman -S --noconfirm linux-neptune linux-neptune-headers
su -l -c '[ ! -d droidcam ] && git clone https://aur.archlinux.org/droidcam.git ; cd droidcam ; makepkg -cCfsi --noconfirm' builduser
rm -rf /var/cache/pacman/pkg/*
kf="$(pacman -Qlq linux-neptune | grep '/usr/lib/modules/[^/]\+/' | head -n 1)"
dkms_src="$(basename /usr/src/v4l2loopback-dc*)"
dkms install "${dkms_src%-*}/${dkms_src##*-}" -k "$(basename "$kf")"
find "${kf}updates/dkms" -type f -name '*.ko.xz' -exec sh -c 'unxz -f "$1" ; objcopy --remove-section .BTF "${1%.*}" ; xz -f "${1%.*}"' _ '{}' \;
tar -cf - "${kf}updates/dkms" | tar -xf - -C "$TMP_PKG_DIR"
tar -cf - /etc/modules-load.d /etc/modprobe.d | tar -xf - -C "$TMP_PKG_DIR"

# finally package the modules tar
tar -cf "$OUT_DIR/v4l2loopback-dc.tar" -C "$TMP_PKG_DIR" .
