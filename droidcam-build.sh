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
# https://github.com/archlinux/svntogit-packages/blob/packages/libjpeg-turbo/trunk/PKGBUILD
echo "Building libjpeg-turbo..."
(
    _name=libjpeg-turbo
    pkgname="$_name"
    pkgver=2.1.4
    #makedepends=(cmake ninja nasm 'java-environment>11')
    #optdepends=('java-runtime>11: for TurboJPEG Java wrapper')
    #provides=(libjpeg libjpeg.so libturbojpeg.so)

    curl -sSLo "$_name-$pkgver.tar.gz" "https://sourceforge.net/projects/$_name/files/$pkgver/$_name-$pkgver.tar.gz"
    echo "511f065767c022da06b6c36299686fa44f83441646f7e33b766c6cfab03f91b0e6bfa456962184071dadaed4057ba9a29cba685383f3eb86a4370a1a53731a70 $_name-$pkgver.tar.gz" > "$_name-$pkgver.tar.gz.sha512"
    sha512sum -c "$_name-$pkgver.tar.gz.sha512"

    tar -xf "$_name-$pkgver.tar.gz"

    cd "$_name-$pkgver"
    cmake -G Ninja \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_INSTALL_LIBDIR=/usr/lib64 \
        -DCMAKE_BUILD_TYPE=None \
        -DENABLE_STATIC=OFF \
        -DWITH_JAVA=OFF \
        -DWITH_JPEG8=ON \
        -W no-dev \
        .
    cmake --build .

    ninja install
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
    pkgver=1.8.2
    url="https://github.com/aramg/${pkgbase}"
    #makedepends=('libappindicator-gtk3' 'gtk3' 'ffmpeg' 'libusbmuxd')

    curl -sSLo "${pkgbase}-${pkgver}.zip" "${url}/archive/v${pkgver}.zip"
    echo "a5a5601efc60ae5e60e189f9ec8c73dab5579e6fdeebdcb9b809b6befb416ecc ${pkgbase}-${pkgver}.zip" > "${pkgbase}-${pkgver}.zip.sha256"
    sha256sum -c "${pkgbase}-${pkgver}.zip.sha256"

    unzip "${pkgbase}-${pkgver}.zip"

    cd "${pkgbase}-${pkgver}"
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

DROIDCAM_VERSION=1.8.2
KERNEL_VERSION="$(tar -tf "$OUT_DIR/v4l2loopback-dc.tar" | grep /v4l2loopback-dc\.ko | sed 's#^[./]*##' | sort -u | tail -n 1 | cut -d/ -f4)"

OUTPUT="DroidCam-${DROIDCAM_VERSION}-${KERNEL_VERSION}-x86_64_SteamDeck.AppImage" ./linuxdeploy-x86_64.AppImage --appdir AppDir \
    --executable AppDir/usr/bin/droidcam \
    --desktop-file AppDir/usr/share/applications/droidcam.desktop \
    --icon-file AppDir/usr/share/pixmaps/droidcam.png \
    --plugin gtk \
    --plugin droidcam \
    --output appimage

mv DroidCam*.AppImage "$OUT_DIR"
