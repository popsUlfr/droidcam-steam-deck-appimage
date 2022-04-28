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
if [ "$(id -u)" -ne 0 ]
then
    echo "Needs to be run as root." >&2
    exit 1
fi
LOWER_DIR="$1"
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
modprobe videodev
modprobe -f v4l2loopback-dc width=640 height=480
modprobe snd-aloop
EOF
chmod +x "$appdir"/usr/bin/droidcam-module-load
mkdir -p "$appdir"/apprun-hooks
cat > "$appdir"/apprun-hooks/linuxdeploy-plugin-droidcam.sh <<\EOF
export PATH="$APPDIR/usr/bin:$PATH"
if ! lsmod | grep -q '^v4l2loopback_dc\b'
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
    if command -v zenity >/dev/null
    then
        has_zenity=1
    else
        has_zenity=0
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
        cat "$TMP_DIR/progress" | zenity --progress --pulsate --no-cancel --auto-close --title="Installing kernel module" --width=300 --text="Installing kernel module" &
        progress_pid="$!"
    fi
    if ! cat "$APPDIR/usr/bin/droidcam-module-load" | sudo -A sh -s "$TMP_DIR/lower" 2>&1 | tee -a "$LOG_FILE" >&2
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
