#!/bin/bash
set -eux
# podman pull centos:7
# podman run --device=/dev/fuse --cap-add SYS_ADMIN --tmpfs /tmp:exec -v ./:/tmp/out --rm -ti ubuntu:20.04 /tmp/out/droidcam-build.sh
# ubuntu image
OUT_DIR="/tmp/out"

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

yum -y update && yum clean all
yum -y install epel-release
yum -y localinstall --nogpgcheck https://download1.rpmfusion.org/free/el/rpmfusion-free-release-7.noarch.rpm
yum -y groupinstall 'Development Tools'
yum -y install pkg-config \
    git \
    cmake \
    nasm \
    ninja-build \
    curl \
    zstd \
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
export MAKEFLAGS="-j$(nproc)"

export pkgdir="/usr"

# libjpeg-turbo
# https://gitlab.archlinux.org/archlinux/packaging/packages/libjpeg-turbo/-/blob/main/PKGBUILD?ref_type=heads
echo "Building libjpeg-turbo..."
(
    pkgname=libjpeg-turbo
    pkgver=3.0.3
    url="https://libjpeg-turbo.org/"
    _url="https://github.com/libjpeg-turbo/libjpeg-turbo/"

    # depends=(glibc)
    # makedepends=(
    #   cmake
    #   ninja
    #   nasm
    #   'java-environment>11'
    #   strip-nondeterminism
    # )
    # optdepends=('java-runtime>11: for TurboJPEG Java wrapper')
    # provides=(
    #   libjpeg
    #   libjpeg.so
    #   libturbojpeg.so
    # )

    curl -sSLo "$pkgname-$pkgver.tar.gz" "$_url/releases/download/$pkgver/$pkgname-$pkgver.tar.gz"
    echo "7c3a6660e7a54527eaa40929f5cc3d519842ffb7e961c32630ae7232b71ecaa19e89dbf5600c61038f0c5db289b607c2316fe9b6b03d482d770bcac29288d129 $pkgname-$pkgver.tar.gz" > "$pkgname-$pkgver.tar.gz.sha512"
    sha512sum -c "$pkgname-$pkgver.tar.gz.sha512"

    tar -xf "$pkgname-$pkgver.tar.gz"

    cd "$pkgname-$pkgver"
    cmake -D CMAKE_INSTALL_PREFIX=/usr \
        -D CMAKE_INSTALL_LIBDIR=/usr/lib64 \
        -D CMAKE_BUILD_TYPE=None \
        -D ENABLE_STATIC=OFF \
        -D WITH_JAVA=OFF \
        -D WITH_JPEG8=ON \
        -G Ninja \
        -W no-dev \
        .
    cmake --build .
    ninja install
    install -vDm 644 jpegint.h /usr/include
)
echo "Building libjpeg-turbo done."

# refresh linker cache
ldconfig

export pkgdir="$BUILD_DIR/AppDir"

# droidcam
# https://aur.archlinux.org/cgit/aur.git/tree/PKGBUILD?h=droidcam
echo "Building droidcam..."
(
    pkgbase=droidcam
    pkgname='droidcam'
    _name=droidcam-linux-client
    pkgver=2.1.3
    url="https://github.com/dev47apps/droidcam-linux-client"
    #makedepends=('alsa-lib' 'ffmpeg' 'gtk3' 'libappindicator-gtk3' 'libjpeg-turbo' 'libusbmuxd' 'speex')
    #depends=('alsa-lib' 'ffmpeg' 'glib2' 'glibc' 'gtk3' 'libappindicator-gtk3' 'libjpeg-turbo' 'libusbmuxd' 'libx11' 'pango' 'speex' 'V4L2LOOPBACK-MODULE')

    curl -sSLo "${pkgbase}-${pkgver}.tar.gz" "${url}/archive/refs/tags/v${pkgver}.tar.gz"
    echo "86d18029364d8ecd8b1a8fcae4cc37122f43683326fe49922b2ce2c8cf01e49d ${pkgbase}-${pkgver}.tar.gz" > "${pkgbase}-${pkgver}.tar.gz.sha256"
    sha256sum -c "${pkgbase}-${pkgver}.tar.gz.sha256"

    tar -xf "${pkgbase}-${pkgver}.tar.gz"

    cd "${_name}-${pkgver}"
    patch -Np1 -i "$OUT_DIR/appimage-app-icon.patch"
    make JPEG_DIR="" JPEG_INCLUDE="" JPEG_LIB="" JPEG="$(pkg-config --libs --cflags libturbojpeg)" CFLAGS="$CFLAGS -std=gnu99"

    install -Dm755 "${pkgbase}" "$pkgdir/usr/bin/${pkgbase}"
    install -Dm755 "${pkgbase}-cli" "$pkgdir/usr/bin/${pkgbase}-cli"
    install -Dm644 icon2.png "${pkgdir}/usr/share/pixmaps/${pkgbase}.png"
    install -Dm644 "${pkgbase}.desktop" "${pkgdir}/usr/share/applications/${pkgbase}.desktop"

    strip -s "$pkgdir/usr/bin/droidcam-cli"
    sed -i -e 's/^\(TryExec=\).*$/\1droidcam/' -e 's/^\(Exec=\).*$/\1droidcam/' -e 's/^\(Icon=\).*$/\1droidcam/' "${pkgdir}/usr/share/applications/${pkgbase}.desktop"
)
echo "Building droidcam done."

mkdir -p AppDir
zstd -d -k -c "$OUT_DIR/v4l2loopback-dc.tar.zst" | tar -xf - -C AppDir

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

DROIDCAM_VERSION=2.1.3
KERNEL_VERSION="$(zstd -d -k -c "$OUT_DIR/v4l2loopback-dc.tar.zst" | tar -tf - | grep /v4l2loopback-dc\.ko | sed 's#^[./]*##' | sort -u | tail -n 1 | cut -d/ -f4)"

OUTPUT="DroidCam-${DROIDCAM_VERSION}-${KERNEL_VERSION}-x86_64_SteamDeck.AppImage" ./linuxdeploy-x86_64.AppImage --appdir AppDir \
    --executable AppDir/usr/bin/droidcam \
    --desktop-file AppDir/usr/share/applications/droidcam.desktop \
    --icon-file AppDir/usr/share/pixmaps/droidcam.png \
    --plugin gtk \
    --plugin droidcam \
    --output appimage

mv DroidCam*.AppImage "$OUT_DIR"
