#!/bin/bash
set -eux
podman pull archlinux:latest
podman pull centos:7
podman run -v ./:/tmp/out --rm -ti archlinux:latest /tmp/out/v4l2loopback-dc-build.sh
podman run --device=/dev/fuse --cap-add SYS_ADMIN --tmpfs /tmp:exec -v ./:/tmp/out --rm -ti centos:7 /tmp/out/droidcam-build.sh
