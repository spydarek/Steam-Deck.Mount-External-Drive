#!/bin/bash

set -Eeuo pipefail

# Steam Deck Mount External Drive
# Modified by darekspy
# https://github.com/spydarek/Steam-Deck.Mount-External-Drive

repo_url="https://raw.githubusercontent.com/spydarek/Steam-Deck.Mount-External-Drive/main"
repo_lib_dir="$repo_url/lib"

tmp_dir="$(mktemp -d /tmp/sdmed-install.XXXXXX)"

rules_install_dir="/etc/udev/rules.d"
service_install_dir="/etc/systemd/system"
script_install_dir="/home/deck/.local/share/scawp/SDMED"

cleanup() {
    rm -rf "$tmp_dir"
}

trap cleanup EXIT

fail() {
    echo "ERROR: $1" >&2
    exit 1
}

# Check required commands
for cmd in curl bash sudo install id uname; do
    command -v "$cmd" >/dev/null 2>&1 || fail "Required command not found: $cmd"
done

# Check Steam Deck configuration
device_name="$(uname --nodename)"
deck_uid="$(id -u deck 2>/dev/null || true)"

if [[ "$device_name" != "steamdeck" || "$deck_uid" != "1000" ]]; then
    if ! command -v zenity >/dev/null 2>&1; then
        fail "This installer is intended for Steam Deck with user deck UID 1000."
    fi

    if ! zenity --question --width=400 \
        --text="This installer is intended for Steam Deck with user deck UID 1000.\nYour system appears to have a different configuration.\nDo you want to continue?"; then
        echo "Installation cancelled."
        exit 0
    fi
fi

# Ask before installation
if command -v zenity >/dev/null 2>&1; then
    if ! zenity --question --width=400 \
        --text="This will install Steam Deck Mount External Drive.\nDo you want to continue?"; then
        echo "Installation cancelled."
        exit 0
    fi
else
    read -r -p "Install Steam Deck Mount External Drive? [y/N] " answer
    [[ "$answer" =~ ^[Yy]$ ]] || exit 0
fi

# Request sudo authentication before making changes
sudo -v || fail "Administrator authentication failed."

echo "Downloading installation files..."

curl --fail --location --silent --show-error \
    -o "$tmp_dir/automount.sh" \
    "$repo_url/automount.sh"

curl --fail --location --silent --show-error \
    -o "$tmp_dir/external-drive-mount@.service" \
    "$repo_lib_dir/external-drive-mount@.service"

curl --fail --location --silent --show-error \
    -o "$tmp_dir/99-steamos-automount.rules" \
    "$repo_lib_dir/99-steamos-automount.rules"

# Check downloaded files
for file in \
    "$tmp_dir/automount.sh" \
    "$tmp_dir/external-drive-mount@.service" \
    "$tmp_dir/99-steamos-automount.rules"; do

    [[ -s "$file" ]] || fail "Downloaded file is empty: $(basename "$file")"
done

# Validate shell syntax
bash -n "$tmp_dir/automount.sh" || fail "automount.sh contains a syntax error."

# Verify expected exFAT options are present
grep -Fq 'uid=1000,gid=1000,fmask=0022,dmask=0002' \
    "$tmp_dir/automount.sh" || fail "The exFAT permission options are missing."

# Verify service and udev rule contents
grep -Fq 'automount.sh add %i' \
    "$tmp_dir/external-drive-mount@.service" || fail "Invalid systemd service file."

grep -Fq 'mmcblk0p' \
    "$tmp_dir/99-steamos-automount.rules" || fail "Expected microSD udev rule is missing."

echo "All downloaded files passed validation."

# Create installation directories
mkdir -p "$script_install_dir"

# Install files
echo "Installing automount.sh..."
sudo install -m 0555 \
    "$tmp_dir/automount.sh" \
    "$script_install_dir/automount.sh"

echo "Installing udev rules..."
sudo install -m 0644 \
    "$tmp_dir/99-steamos-automount.rules" \
    "$rules_install_dir/99-steamos-automount.rules"

echo "Installing systemd service..."
sudo install -m 0644 \
    "$tmp_dir/external-drive-mount@.service" \
    "$service_install_dir/external-drive-mount@.service"

# Remove obsolete rules from previous versions
sudo rm -f \
    "$rules_install_dir/99-external-drive-mount.rules" \
    "$rules_install_dir/98-external-drive-mount.rules"

# Reload system configuration
echo "Reloading udev and systemd..."
sudo udevadm control --reload
sudo systemctl daemon-reload

echo
echo "Installation completed successfully."
echo "A restart is required."

if command -v zenity >/dev/null 2>&1; then
    if zenity --question --width=400 \
        --text="Installation completed.\nRestart Steam Deck now?"; then
        sudo systemctl reboot
    else
        echo "Restart skipped. Restart manually when convenient."
    fi
else
    read -r -p "Restart now? [y/N] " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        sudo systemctl reboot
    else
        echo "Restart skipped. Restart manually when convenient."
    fi
fi
