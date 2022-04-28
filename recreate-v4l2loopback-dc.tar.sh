#!/bin/bash
TMP_DIR="$(mktemp -d)"
cleanup() {
    if [[ -d "$TMP_DIR" ]]; then
        rm -rf "$TMP_DIR"
    fi
}
trap cleanup EXIT

mkdir "$TMP_DIR/root"
fakeroot -i "$TMP_DIR/fakeroot" -s "$TMP_DIR/fakeroot" -- tar -xpf v4l2loopback-dc.tar -C "$TMP_DIR/root"
fakeroot -i "$TMP_DIR/fakeroot" -s "$TMP_DIR/fakeroot" -- tar -cf v4l2loopback-dc.new.tar -C "$TMP_DIR/root" .
mv -f v4l2loopback-dc.new.tar v4l2loopback-dc.tar
