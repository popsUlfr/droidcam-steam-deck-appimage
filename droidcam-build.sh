#!/bin/bash
set -eux
# podman pull centos:7
# podman run --device=/dev/fuse --cap-add SYS_ADMIN --tmpfs /tmp:exec -v ./:/tmp/out --rm -ti ubuntu:20.04 /tmp/out/droidcam-build.sh
# ubuntu image
OUT_DIR="/tmp/out"
DEST="/usr"
DROIDCAM_VERSION=1.8.2
DROIDCAM_URL='https://github.com/dev47apps/droidcam.git'
LIBJPEG_TURBO_VERSION=2.1.3
KERNEL_VERSION="$(tar -tf "$OUT_DIR/v4l2loopback-dc.tar" | grep /v4l2loopback-dc\.ko | sed 's#^[./]*##' | sort -u | tail -n 1 | cut -d/ -f4)"

# building in temporary directory to keep system clean
# use RAM disk if possible (as in: not building on CI system like Travis, and RAM disk is available)
# if [[ -z "$CI" ]] && [[ -d /dev/shm ]]; then
#     TEMP_BASE=/dev/shm
# else
#     TEMP_BASE=/tmp
# fi

TEMP_BASE=/tmp
BUILD_DIR="$(mktemp -d -p "$TEMP_BASE" appimage-build-XXXXXX)"

# make sure to clean up build dir, even if errors occur
cleanup() {
    if [[ -d "$BUILD_DIR" ]]; then
        rm -rf "$BUILD_DIR"
    fi
}
trap cleanup EXIT

cd "$BUILD_DIR"

# https://aur.archlinux.org/cgit/aur.git/tree/PKGBUILD?h=droidcam
yum -y update && yum clean all
yum -y install epel-release
yum -y localinstall --nogpgcheck https://download1.rpmfusion.org/free/el/rpmfusion-free-release-7.noarch.rpm
yum -y groupinstall 'Development Tools'
yum -y install pkg-config \
    git \
    cmake \
    nasm \
    curl \
    fuse \
    fuse-libs \
    ffmpeg \
    ffmpeg-devel \
    alsa-lib \
    alsa-lib-devel \
    speex \
    speex-devel \
    libusbmuxd \
    libusbmuxd-devel \
    libplist \
    libplist-devel \
    libappindicator-gtk3 \
    libappindicator-gtk3-devel \
    librsvg2 \
    librsvg2-devel

# source the default compiler flags
export CFLAGS="$(rpm --eval "%{optflags}")"
export CXXFLAGS="$CFLAGS"

# compile latest libjpeg-turbo
# https://github.com/archlinux/svntogit-packages/blob/packages/libjpeg-turbo/trunk/PKGBUILD
curl -sSLo libjpeg-turbo-2.1.3.tar.gz "https://sourceforge.net/projects/libjpeg-turbo/files/${LIBJPEG_TURBO_VERSION}/libjpeg-turbo-${LIBJPEG_TURBO_VERSION}.tar.gz"
tar -xf "libjpeg-turbo-${LIBJPEG_TURBO_VERSION}.tar.gz"
mkdir -p build
cd build
cmake -DCMAKE_INSTALL_PREFIX="$DEST" -DCMAKE_INSTALL_LIBDIR="$DEST/lib64" -DCMAKE_BUILD_TYPE=None -DWITH_JPEG8=ON -Wno-dev "../libjpeg-turbo-${LIBJPEG_TURBO_VERSION}"
make -j$(nproc) VERBOSE=1
make VERBOSE=1 install
cd ..

# refresh linker cache
ldconfig

# build droidcam
git clone "$DROIDCAM_URL"
cd droidcam
git checkout v"$DROIDCAM_VERSION"
patch -Np1 -i "$OUT_DIR/appimage-app-icon.patch"
make -j$(nproc) JPEG_DIR="" JPEG_INCLUDE="" JPEG_LIB="" JPEG="$(pkg-config --libs --cflags libturbojpeg)" CFLAGS="$CFLAGS -std=gnu99"

install -Dm755 droidcam "$BUILD_DIR/AppDir/usr/bin/droidcam"
install -Dm755 droidcam-cli "$BUILD_DIR/AppDir/usr/bin/droidcam-cli"
strip -s "$BUILD_DIR/AppDir/usr/bin/droidcam-cli"
install -Dm644 icon2.png "$BUILD_DIR/AppDir/usr/share/pixmaps/droidcam.png"
sed -i -e 's/^\(TryExec=\).*$/\1droidcam/' -e 's/^\(Exec=\).*$/\1droidcam/' -e 's/^\(Icon=\).*$/\1droidcam/' droidcam.desktop
install -Dm644 droidcam.desktop "$BUILD_DIR/AppDir/usr/share/applications/droidcam.desktop"

cd ..

mkdir -p AppDir
tar -xf "$OUT_DIR/v4l2loopback-dc.tar" -C AppDir

# create appimages
curl -sSLo linuxdeploy-x86_64.AppImage https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage
chmod +x linuxdeploy-x86_64.AppImage
curl -sSLo linuxdeploy-plugin-appimage-x86_64.AppImage https://github.com/linuxdeploy/linuxdeploy-plugin-appimage/releases/download/continuous/linuxdeploy-plugin-appimage-x86_64.AppImage
chmod +x linuxdeploy-plugin-appimage-x86_64.AppImage
curl -sSLo linuxdeploy-plugin-gtk.sh https://raw.githubusercontent.com/linuxdeploy/linuxdeploy-plugin-gtk/master/linuxdeploy-plugin-gtk.sh
chmod +x linuxdeploy-plugin-gtk.sh
cp "$OUT_DIR/linuxdeploy-plugin-droidcam.sh" .

# fix girepository-1.0 path
mkdir -p /usr/lib/x86_64-linux-gnu/girepository-1.0

OUTPUT="DroidCam-${DROIDCAM_VERSION}-${KERNEL_VERSION}-x86_64_SteamDeck.AppImage" ./linuxdeploy-x86_64.AppImage --appdir AppDir \
    --executable AppDir/usr/bin/droidcam \
    --desktop-file AppDir/usr/share/applications/droidcam.desktop \
    --icon-file AppDir/usr/share/pixmaps/droidcam.png \
    --plugin gtk \
    --plugin droidcam \
    --output appimage

mv DroidCam*.AppImage "$OUT_DIR"
