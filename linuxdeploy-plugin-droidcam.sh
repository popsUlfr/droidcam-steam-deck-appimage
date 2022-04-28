#! /bin/bash

# exit whenever a command called in this script fails
set -e

appdir=""

show_usage() {
    echo "Usage: bash $0 --appdir <AppDir>"
}

while [ "$1" != "" ]; do
    case "$1" in
        --plugin-api-version)
            echo "0"
            exit 0
            ;;
        --appdir)
            appdir="$2"
            shift
            shift
            ;;
        *)
            echo "Invalid argument: $1"
            echo
            show_usage
            exit 2
    esac
done

if [[ "$appdir" == "" ]]; then
    show_usage
    exit 2
fi

echo "linuxdeploy-plugin-droidcam"
echo "\$LINUXDEPLOY: \"$LINUXDEPLOY\""

# Remove unused files
rm -rf "$appdir"/usr/share/doc "$appdir"/usr/share/man

# install a path AppRun hook
# usually, they're not supposed to print anything, but remain as silent as possible
set -x
mkdir -p "$appdir"/usr/bin
cat > "$appdir"/usr/bin/zenity-askpass <<\EOF
#!/bin/sh
exec zenity --password --title="$1"
EOF
chmod +x "$appdir"/usr/bin/zenity-askpass
cat > "$appdir"/usr/bin/droidcam-module-load <<\EOF
#!/bin/sh
set -e
if [ "$(id -u)" -ne 0 ]
then
    echo "Needs to be run as root." >&2
    exit 1
fi
V4L2LOOPBACK_DC_PARAMS="${V4L2LOOPBACK_DC_PARAMS:-width=640 height=480}"
LOWER_DIR="$1"
if [ -n "$2" ]
then
    V4L2LOOPBACK_DC_PARAMS="$2"
fi
if ! modinfo v4l2loopback-dc >/dev/null 2>&1
then
    TMP_DIR="$(mktemp -d -p /tmp appimage-droidcam.XXXXXX)"
    cleanup() {
        if [ -d "$TMP_DIR" ]
        then
            umount -l "/usr/lib/modules/$(uname -r)" || true
            rm -rf "$TMP_DIR" || true
        fi
    }
    trap cleanup EXIT
    mkdir "$TMP_DIR/upper" "$TMP_DIR/work"
    mount -t overlay -o lowerdir="$LOWER_DIR":"/usr/lib/modules/$(uname -r)",upperdir="$TMP_DIR/upper",workdir="$TMP_DIR/work" overlay "/usr/lib/modules/$(uname -r)"
    depmod
fi
if lsmod | grep -q '^v4l2loopback_dc\b'
then
    if ! modprobe -r v4l2loopback-dc
    then
        rmmod -f v4l2loopback-dc
    fi
fi
modprobe videodev
modprobe -f v4l2loopback-dc $V4L2LOOPBACK_DC_PARAMS
modprobe snd-aloop
EOF
chmod +x "$appdir"/usr/bin/droidcam-module-load
mkdir -p "$appdir"/apprun-hooks
cat > "$appdir"/apprun-hooks/linuxdeploy-plugin-droidcam.sh <<\EOF
export PATH="$APPDIR/usr/bin:$PATH"
if command -v zenity >/dev/null
then
    has_zenity=1
else
    has_zenity=0
fi
if [ -z "$V4L2LOOPBACK_DC_PARAMS" ] && [ "$has_zenity" -eq 1 ]
then
    curr_width="640"
    curr_height="480"
    if [ -f /sys/module/v4l2loopback_dc/parameters/width ]
    then
        curr_width="$(cat /sys/module/v4l2loopback_dc/parameters/width)"
    fi
    if [ -f /sys/module/v4l2loopback_dc/parameters/height ]
    then
        curr_height="$(cat /sys/module/v4l2loopback_dc/parameters/height)"
    fi
    if res="$(printf '640x480\n800x600\n1024x576\n1280x720\n1920x1080\n' | zenity \
        --list \
        --title="DroidCam Resolution" \
        --width=300 \
        --height=300 \
        --text="Resolution to use for the webcam.\nCurrent size is ${curr_width}x${curr_height}.\nDefault is 640x480.\nV4L2LOOPBACK_DC_PARAMS environment variable can be set with the parameters to pass to the module.\ne.g.: V4L2LOOPBACK_DC_PARAMS=\"width=640 height=480 video_nr=(-1|0..)\"" \
        --column=Resolution)" && [ -n "$res" ]
    then
        V4L2LOOPBACK_DC_PARAMS="width=$(echo "$res" | cut -dx -f1) height=$(echo "$res" | cut -dx -f2)"
        export V4L2LOOPBACK_DC_PARAMS
    fi
fi
reload_module=0
if [ -n "$V4L2LOOPBACK_DC_PARAMS" ]
then
    width="$(echo "$V4L2LOOPBACK_DC_PARAMS" | sed -n 's/^.*\bwidth=\([0-9]\+\).*$/\1/p')"
    height="$(echo "$V4L2LOOPBACK_DC_PARAMS" | sed -n 's/^.*\bheight=\([0-9]\+\).*$/\1/p')"
    video_nr="$(echo "$V4L2LOOPBACK_DC_PARAMS" | sed -n 's/^.*\bvideo_nr=\(-\?[0-9]\+\).*$/\1/p')"
    if { [ -n "$width" ] && [ -f /sys/module/v4l2loopback_dc/parameters/width ] && \
        [ "$width" != "$(cat /sys/module/v4l2loopback_dc/parameters/width)" ] ;} || \
        { [ -n "$height" ] && [ -f /sys/module/v4l2loopback_dc/parameters/height ] && \
        [ "$height" != "$(cat /sys/module/v4l2loopback_dc/parameters/height)" ] ;} || \
        { [ -n "$video_nr" ] && [ -f /sys/module/v4l2loopback_dc/parameters/video_nr ] && \
        [ "$video_nr" != "$(cat /sys/module/v4l2loopback_dc/parameters/video_nr)" ] ;}
    then
        reload_module=1
    fi
fi
if [ "$reload_module" -eq 1 ] || ! lsmod | grep -q '^v4l2loopback_dc\b'
then
    if [ -z "$SUDO_ASKPASS" ]
    then
        for ap in ksshaskpass ssh-askpass zenity
        do
            if apc="$(command -v "$ap")"
            then
                if [ "$ap" = "zenity" ]
                then
                    apc="$(command -v "zenity-askpass")"
                fi
                export SUDO_ASKPASS="$apc"
                break
            fi
        done
    fi
    if [ ! -d "$APPDIR/usr/lib/modules/$(uname -r)" ]
    then
        if ! modinfo v4l2loopback_dc >/dev/null 2>&1
        then
            echo "WARNING! No kernel module found that matches current kernel. The appimage may need to be updated."
            if [ "$has_zenity" -eq 1 ]
            then
                zenity --warning --width=300 --text="WARNING! No kernel module found that matches current kernel. The appimage may need to be updated." || true
            fi
        fi
        LOWER_DIR="$(find "$APPDIR/usr/lib/modules" -mindepth 1 -maxdepth 1 -type d | tail -n 1)"
    else
        LOWER_DIR="$APPDIR/usr/lib/modules/$(uname -r)"
    fi
    TMP_DIR="$(mktemp -d -p /tmp appimage-droidcam.XXXXXX)"
    mkdir "$TMP_DIR/lower"
    cp -a "$LOWER_DIR"/. "$TMP_DIR/lower/"
    LOG_FILE="$TMP_DIR/appimage-droidcam.log"
    touch "$LOG_FILE"
    progress_pid=
    if [ "$has_zenity" -eq 1 ]
    then
        mkfifo -m 600 "$TMP_DIR/progress"
        cat "$TMP_DIR/progress" | zenity --progress --pulsate --no-cancel --auto-close --title="DroidCam - Installing kernel module" --width=300 --text="Installing kernel module" &
        progress_pid="$!"
    fi
    sudo_status="$TMP_DIR/sudo_status"
    if ! cat "$APPDIR/usr/bin/droidcam-module-load" | { sudo -A sh -s "$TMP_DIR/lower" "$V4L2LOOPBACK_DC_PARAMS" 2>&1 || echo "$?" > "$sudo_status" ;} | tee -a "$LOG_FILE" >&2 || \
        { [ -f "$sudo_status" ] && [ "$(cat "$sudo_status")" -ne 0 ] ;}
    then
        echo "ERROR! Failed to load the needed modules." 2>&1 | tee -a "$LOG_FILE" >&2
        zenity --error --width=300 --title="ERROR! Failed to load the needed modules." --text="$(cat "$LOG_FILE")" || true
    fi
    if [ "$has_zenity" -eq 1 ]
    then
        echo 100 > "$TMP_DIR/progress"
        wait "$progress_pid" || true
    fi
    rm -rf "$TMP_DIR"
fi
if basename "$ARGV0" | grep -q '^droidcam-cli'
then
    exec droidcam-cli "$@"
fi
EOF
