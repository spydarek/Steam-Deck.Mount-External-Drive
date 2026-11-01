#!/bin/bash
# Steam Deck Mount External Drive by scawp
# Modified by spydarek
# exFAT permissions fix for Steam Deck user deck

set -e

repo_url="https://raw.githubusercontent.com/spydarek/Steam-Deck.Mount-External-Drive/main"
repo_lib_dir="$repo_url/lib"

tmp_dir="/tmp/scawp.SDMED.install"

rules_install_dir="/etc/udev/rules.d"
service_install_dir="/etc/systemd/system"
script_install_dir="/home/deck/.local/share/scawp/SDMED"

device_name="$(uname --nodename)"
user="$(id -u deck)"

if [ "$device_name" != "steamdeck" ] || [ "$user" != "1000" ]; then
  if ! zenity --question --width=400 \
    --text="This code has been written specifically for the Steam Deck with user Deck \
    \nIt appears you are running on a different system/non-standard configuration. \
    \nAre you sure you want to continue?"; then
    echo "Installation cancelled."
    exit 1
  fi
fi

function install_automount () {
  if ! zenity --question --width=400 \
    --text="Read $repo_url/README.md before proceeding. \
    \nDo you want to install the Auto-Mount Service?"; then
    echo "Installation cancelled."
    exit 0
  fi

  echo "Making tmp folder $tmp_dir"
  mkdir -p "$tmp_dir"

  echo "Downloading Required Files"
  curl --fail --location --silent --show-error -o "$tmp_dir/automount.sh" "$repo_url/automount.sh"
  curl --fail --location --silent --show-error -o "$tmp_dir/external-drive-mount@.service" "$repo_lib_dir/external-drive-mount@.service"
  curl --fail --location --silent --show-error -o "$tmp_dir/99-steamos-automount.rules" "$repo_lib_dir/99-steamos-automount.rules"

  echo "Applying exFAT permissions fix"

  if ! grep -Fq 'mount -t exfat -o uid=1000,gid=1000,fmask=0022,dmask=0002' "$tmp_dir/automount.sh"; then
    sed -i '/^[[:space:]]*mount "\$1" "\/run\/media\/deck\/\$label"$/c\
    if [ "$fs_type" = "exfat" ]; then\
      mount -t exfat -o uid=1000,gid=1000,fmask=0022,dmask=0002 "$1" "/run/media/deck/$label"\
    else\
      mount "$1" "/run/media/deck/$label"\
    fi' "$tmp_dir/automount.sh"
  fi

  if ! grep -Fq 'mount -t exfat -o uid=1000,gid=1000,fmask=0022,dmask=0002' "$tmp_dir/automount.sh"; then
    echo "ERROR: Could not apply exFAT fix. Installation stopped."
    exit 1
  fi

  if ! bash -n "$tmp_dir/automount.sh"; then
    echo "ERROR: automount.sh contains syntax errors."
    exit 1
  fi

  echo "exFAT fix verified"

  echo "Making script folder $script_install_dir"
  mkdir -p "$script_install_dir"

  echo "Copying automount.sh"
  sudo cp "$tmp_dir/automount.sh" "$script_install_dir/automount.sh"

  echo "Adding Execute and Removing Write Permissions"
  sudo chmod 555 "$script_install_dir/automount.sh"

  echo "Copying udev rules"
  sudo cp "$tmp_dir/99-steamos-automount.rules" "$rules_install_dir/99-steamos-automount.rules"

  if [ -f "$rules_install_dir/99-external-drive-mount.rules" ]; then
    sudo rm "$rules_install_dir/99-external-drive-mount.rules"
  fi

  if [ -f "$rules_install_dir/98-external-drive-mount.rules" ]; then
    sudo rm "$rules_install_dir/98-external-drive-mount.rules"
  fi

  echo "Copying systemd service"
  sudo cp "$tmp_dir/external-drive-mount@.service" "$service_install_dir/external-drive-mount@.service"

  echo "Reloading Services"
  sudo udevadm control --reload
  sudo systemctl daemon-reload

  echo "Installation completed successfully."
}

install_automount

if ! zenity --question --width=400 \
  --text="Restart Required to take effect, \
  \nDo you want to Restart Now?"; then
  echo "Installation completed. Restart later to apply changes."
  exit 0
fi

echo "Restarting Steam Deck..."
sudo reboot
