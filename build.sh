#!/bin/bash
set -eux
podman pull archlinux:latest
podman pull centos:7
repo_suffixes=('' '-3.0' '-3.1' '-3.2' '-3.3' '-3.3.1' '-3.3.2' '-3.3.3' '-rel' '-beta' '-main' '-staging')
for s in "${repo_suffixes[@]}"
do
    podman run -v ./:/tmp/out --rm -ti archlinux:latest /tmp/out/v4l2loopback-dc-build.sh "$s"
done
podman run --device=/dev/fuse --cap-add SYS_ADMIN --tmpfs /tmp:exec -v ./:/tmp/out --rm -ti centos:7 /tmp/out/droidcam-build.sh
