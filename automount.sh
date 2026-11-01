#!/bin/bash

set -euo pipefail

# Originally from https://serverfault.com/a/767079
# Modified by spydarek
# Added exFAT write permissions for Steam Deck user

# This script is called from our systemd unit file to mount or unmount
# a USB drive.

usage()
{
    echo "Usage: $0 {add|remove|retrigger} device_name (e.g. sdb1)"
    exit 1
}

if [[ $# -ne 2 ]]; then
    usage
fi

ACTION=$1
DEVBASE=$2
DEVICE="/dev/${DEVBASE}"

MOUNT_LOCK="/var/run/jupiter-automount-${DEVBASE//\//_}.lock"

exec 9<>"$MOUNT_LOCK"
if ! flock -n 9; then
    echo "$MOUNT_LOCK is active: ignoring action $ACTION"
    exit 1
fi

wait_steam()
{
    local i=0
    local wait=$1
    echo "Waiting up to $wait seconds for steam to load"
    while ! pgrep -x steamwebhelper &>/dev/null && (( i++ < wait )); do
        sleep 1
    done
}

send_steam_url()
{
    local command="$1"
    local arg="$2"
    local encoded
    encoded=$(urlencode "$arg")

    if pgrep -x "steam" > /dev/null; then
        systemd-run -M 1000@ --user --collect --wait sh -c "./.steam/root/ubuntu12_32/steam steam://${command}/${encoded@Q}"
        echo "Sent URL to steam: steam://${command}/${arg} (steam://${command}/${encoded})"
    else
        echo "Could not send steam URL steam://${command}/${arg} -- steam not running"
    fi
}

urlencode()
{
    [ -z "$1" ] || echo -n "$@" | hexdump -v -e '/1 "%02x"' | sed 's/\(..\)/%\1/g'
}

do_mount()
{
    declare -i ret

    readonly FSCK_ERROR=1
    readonly MOUNT_ERROR=2

    dev_json=$(lsblk -o PATH,LABEL,FSTYPE --json -- "$DEVICE" | jq '.blockdevices[0]')
    ID_FS_LABEL=$(jq -r '.label | select(type == "string")' <<< "$dev_json")
    ID_FS_TYPE=$(jq -r '.fstype | select(type == "string")' <<< "$dev_json")

    OPTS="rw,noatime"

    case "${ID_FS_TYPE}" in
        "ntfs")
            echo "FSType is NTFS"
            ;;
        "exfat")
            echo "FSType is exFAT"
            OPTS="rw,noatime,uid=1000,gid=1000,fmask=0022,dmask=0002"
            ;;
        "btrfs")
            echo "FSType is btrfs"
            ;;
        "ext4")
            echo "FSType is ext4"
            ;;
        *)
            echo "Error mounting ${DEVICE}: unsupported fstype: ${ID_FS_TYPE} - ${dev_json}"
            rm -f "${MOUNT_LOCK}"
            exit 2
            ;;
    esac

    ret=0

    reply=$(busctl call --allow-interactive-authorization=false --expect-reply=true --json=short \
        org.freedesktop.UDisks2 \
        /org/freedesktop/UDisks2/block_devices/"${DEVBASE}" \
        org.freedesktop.UDisks2.Filesystem \
        Mount 'a{sv}' 3 \
        as-user s deck \
        auth.no_user_interaction b true \
        options s "$OPTS") || ret=$?

    if (( ret != 0 )); then
        send_steam_url "system/devicemountresult" "${DEVBASE}/${MOUNT_ERROR}"
        echo "Error mounting ${DEVICE} (status = $ret)"
        exit 1
    fi

    mount_point=$(jq -r '.data[0] | select(type == "string")' <<< "$reply" || true)

    if [[ -z $mount_point ]]; then
        echo "Error when mounting ${DEVICE}: udisks returned success but could not parse reply:"
        echo "---"$'\n'"$reply"$'\n'"---"
        exit 1
    fi

    if [[ ${ID_FS_TYPE} == "exfat" ]]; then
        echo "exFAT mounted. Skipping Steam library registration."
        exit 0
    fi

    case "${DEVBASE}" in
        mmcblk0p*)
            if [[ -z "${ID_FS_LABEL}" ]]; then
                old_mount_point="/run/media/${DEVBASE}"
            else
                old_mount_point="/run/media/${mount_point##*/}"
            fi

            if [[ ! -d "${old_mount_point}" ]]; then
                rm -f -- "${old_mount_point}"
                ln -s -- "${mount_point}" "${old_mount_point}"
            fi
            ;;
    esac

    echo "**** Mounted ${DEVICE} at ${mount_point} ****"

    if [ -f "${mount_point}/libraryfolder.vdf" ]; then
        send_steam_url "addlibraryfolder" "${mount_point}"
    else
        mkdir -p "${mount_point}/SteamLibrary"
        chown deck:deck "${mount_point}/SteamLibrary"
        send_steam_url "addlibraryfolder" "${mount_point}/SteamLibrary"
    fi
}

do_unmount()
{
    local mount_point
    mount_point=$(findmnt -fno TARGET "${DEVICE}" || true)

    if [[ -n $mount_point ]]; then
        find /run/media -maxdepth 1 -xdev -type l -lname "${mount_point}" -exec rm -- {} \;
    else
        find /run/media -maxdepth 1 -xdev -xtype l -exec rm -- {} \;
    fi
}

do_retrigger()
{
    local mount_point
    mount_point=$(findmnt -fno TARGET "${DEVICE}" || true)

    [[ -n $mount_point ]] || return 0

    wait_steam 10
    sleep 6
    send_steam_url "addlibraryfolder" "${mount_point}"
}

case "${ACTION}" in
    add)
        do_mount
        ;;
    remove)
        do_unmount
        ;;
    retrigger)
        do_retrigger
        ;;
    *)
        usage
        ;;
esac
