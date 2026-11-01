#!/usr/bin/env bash
# Steam Deck Mount External Drive
# Modified by spydarek
# Validates all downloaded files and keeps backups.

set -Eeuo pipefail

repo_url="https://raw.githubusercontent.com/spydarek/Steam-Deck.Mount-External-Drive/main"
repo_lib_dir="$repo_url/lib"

script_install_dir="/home/deck/.local/share/scawp/SDMED"
service_install_dir="/etc/systemd/system"
rules_install_dir="/etc/udev/rules.d"

tmp_dir="$(mktemp -d /tmp/scawp.SDMED.install.XXXXXX)"
backup_root="$script_install_dir/backups/$(date +%Y%m%d-%H%M%S)"

targets=()
backup_files=()
existed_files=()
installation_started=0

cleanup() {
    rm -rf -- "$tmp_dir"
}

rollback() {
    local i

    echo
    echo "ERROR: Installation failed."
    echo "Restoring previous files..."

    for ((i=${#targets[@]}-1; i>=0; i--)); do
        if [[ "${existed_files[$i]}" == "yes" ]]; then
            sudo cp -a -- "${backup_files[$i]}" "${targets[$i]}" || true
        else
            sudo rm -f -- "${targets[$i]}" || true
        fi
    done

    sudo udevadm control --reload-rules >/dev/null 2>&1 || true
    sudo systemctl daemon-reload >/dev/null 2>&1 || true

    echo "Rollback finished."
}

on_error() {
    local status=$?
    trap - ERR

    if (( installation_started )); then
        rollback
    fi

    exit "$status"
}

trap cleanup EXIT
trap on_error ERR

for cmd in curl sudo zenity bash grep install; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "Missing required command: $cmd"
        exit 1
    }
done

if [[ "$(uname -n)" != "steamdeck" ]] ||
   [[ "$(id -u deck 2>/dev/null || true)" != "1000" ]]; then

    if ! zenity --question --width=420 \
        --text="This installer is intended for Steam Deck with user deck (UID 1000). Continue anyway?"; then
        echo "Installation cancelled."
        exit 1
    fi
fi

if ! zenity --question --width=440 \
    --text="Install SDMED from the spydarek repository? Existing files will be backed up before installation."; then
    echo "Installation cancelled."
    exit 0
fi

mkdir -p "$tmp_dir/download" "$tmp_dir/stage"

fetch() {
    local url="$1"
    local output="$2"

    curl --fail --location --silent --show-error \
        --retry 2 --retry-delay 1 \
        "$url" --output "$output"

    [[ -s "$output" ]] || {
        echo "ERROR: Downloaded file is empty: $output"
        return 1
    }
}

echo "Downloading installation files..."

fetch "$repo_url/automount.sh" \
    "$tmp_dir/download/automount.sh"

fetch "$repo_lib_dir/external-drive-mount@.service" \
    "$tmp_dir/download/external-drive-mount@.service"

fetch "$repo_lib_dir/99-steamos-automount.rules" \
    "$tmp_dir/download/99-steamos-automount.rules"

auto="$tmp_dir/download/automount.sh"
service="$tmp_dir/download/external-drive-mount@.service"
rules="$tmp_dir/download/99-steamos-automount.rules"

echo "Validating downloaded files..."

bash -n "$auto"

grep -Fq 'uid=1000,gid=1000,fmask=0022,dmask=0002' "$auto" || {
    echo "ERROR: exFAT permissions options are missing."
    exit 1
}

grep -Fq 'org.freedesktop.UDisks2.Filesystem' "$auto" || {
    echo "ERROR: UDisks2 mount implementation not found."
    exit 1
}

grep -Fq 'ExecStart=/home/deck/.local/share/scawp/SDMED/automount.sh add %i' "$service" || {
    echo "ERROR: Incorrect service ExecStart."
    exit 1
}

grep -Fq 'ExecStop=/home/deck/.local/share/scawp/SDMED/automount.sh remove %i' "$service" || {
    echo "ERROR: Incorrect service ExecStop."
    exit 1
}

grep -Fq 'external-drive-mount@%k.service' "$rules" || {
    echo "ERROR: udev service trigger is missing."
    exit 1
}

grep -Fq 'ACTION=="add"' "$rules" || {
    echo "ERROR: udev add rule is missing."
    exit 1
}

grep -Fq 'ACTION=="remove"' "$rules" || {
    echo "ERROR: udev remove rule is missing."
    exit 1
}

echo "All downloaded files passed validation."

install -m 555 "$auto" \
    "$tmp_dir/stage/automount.sh"

install -m 644 "$service" \
    "$tmp_dir/stage/external-drive-mount@.service"

install -m 644 "$rules" \
    "$tmp_dir/stage/99-steamos-automount.rules"

targets=(
    "$script_install_dir/automount.sh"
    "$service_install_dir/external-drive-mount@.service"
    "$rules_install_dir/99-steamos-automount.rules"
)

staged=(
    "$tmp_dir/stage/automount.sh"
    "$tmp_dir/stage/external-drive-mount@.service"
    "$tmp_dir/stage/99-steamos-automount.rules"
)

echo "Preparing installation directories..."

sudo install -d -o deck -g deck -m 755 "$script_install_dir"
sudo install -d -o deck -g deck -m 700 "$backup_root"

echo "Creating backups..."

for i in "${!targets[@]}"; do
    if sudo test -e "${targets[$i]}"; then
        existed_files+=(yes)
        sudo cp -a -- "${targets[$i]}" "$backup_root/$i"
    else
        existed_files+=(no)
    fi

    backup_files+=("$backup_root/$i")
done

echo "Installing files..."

installation_started=1

sudo install -D -o root -g root -m 555 \
    "${staged[0]}" "${targets[0]}"

sudo install -D -o root -g root -m 644 \
    "${staged[1]}" "${targets[1]}"

sudo install -D -o root -g root -m 644 \
    "${staged[2]}" "${targets[2]}"

echo "Reloading udev and systemd..."

sudo udevadm control --reload-rules
sudo systemctl daemon-reload

installation_started=0
trap - ERR

echo
echo "Installation completed successfully."
echo "Backups saved in:"
echo "$backup_root"

if zenity --question --width=420 \
    --text="Installation completed. Restart the Steam Deck now?"; then

    echo "Restarting Steam Deck..."
    sudo systemctl reboot
else
    echo "Restart later to activate the changes."
fi
