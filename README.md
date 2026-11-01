# Steam-Deck.Mount-External-Drive 3.5

Script to Auto-Mount NTFS, BTRFS & exFAT SD Cards, External USB Drives (or SSD Docks) & Internal Partitions (If you Dual-Boot) on the Steam Deck.

NTFS & BTRFS partitions containing a SteamLibrary at root level or in a folder named `SteamLibrary` will automatically be added to Steam.

exFAT is not supported as a SteamLibrary filesystem, but drives will be mounted for use with other launchers, media, ROMs and general file storage.

---

# Added automatic exFAT mount permissions for Steam Deck (darekspy)

This fork adds automatic ownership and permission handling for exFAT drives mounted by SDMED.

### Changes

- Added `uid=1000` and `gid=1000` mount options to assign exFAT file ownership to the Steam Deck `deck` user.
- Added `fmask=0022` and `dmask=0002` to configure file and directory permissions.
- Preserved the original UDisks2 mounting mechanism.
- Preserved existing NTFS, Btrfs and ext4 mounting behavior.
- Kept automatic Steam Library registration for supported filesystems.
- Preserved the original behavior of skipping Steam Library registration for exFAT drives.
- Updated the installer to download and install the modified automount script.

### Why this change?

By default, automatically mounted exFAT drives may not have the ownership and permissions expected by the `deck` user.

These mount options are intended to provide the correct ownership and read/write access, allowing the user to create, copy, modify and delete files on automatically mounted exFAT drives.

The exFAT filesystem is retained, so the drive remains compatible with Windows.

**Note:** Actual mounting behavior and permissions should be verified on SteamOS after installation.

---

# "This is cool! How can I thank you?"

Why not drop me a sub over on my YouTube channel ;)

[Chinballs Gaming](https://www.youtube.com/chinballsTV?sub_confirmation=1)

Also check out all these other things I'm making:

[Steam-Deck.Tools-List](https://github.com/scawp/Steam-Deck.Tools-List)

---

# SteamOS 3.5

SteamOS 3.5 now supports external ext4 drives out of the box, so see **Uninstall** if that's all you need!

---

# How does this work?

This script is basically a mirror of Valve's own Auto-Mount script, which lives at:

`/usr/lib/hwsupport/steamos-automount.sh`

It adds support for `ntfs`, `btrfs` and `exFAT`, as well as rules for internal partitions.

Additional RegEx has been added to the rules to allow the mounting of full-disk-formatted drives (for example, drives without a partition table). This means devices such as `sda` or `mmcblk0` can be mounted, as well as partitions such as `sda1` or `mmcblk0p1`.

SteamOS's original rule is located at:

`/usr/lib/udev/rules.d/99-steamos-automount.rules`

Because SteamOS has a read-only filesystem, files in `/usr/` cannot be changed without disabling the read-only filesystem. However, systemd and udev rules can be overridden through higher-priority configuration directories.

By adding a rule with the same name in `/etc/udev/rules.d/`, the original SteamOS rule can be overridden without modifying the system files.

A udev rule is added to:

`/etc/udev/rules.d/99-steamos-automount.rules`

This takes priority over:

`/usr/lib/udev/rules.d/99-steamos-automount.rules`

The rule then calls the systemd service:

`/etc/systemd/system/external-drive-mount@[device].service`

The service runs:

`/home/deck/.local/share/scawp/SDMED/automount.sh`

This automatically mounts supported SD cards, external USB drives and internal partitions.

`/etc/fstab` is not required for mounting in this way. However, if a device has an fstab entry, these scripts will still work.

---

# Video Guide

[https://www.youtube.com/watch?v=Yglf1EKBv2A](https://www.youtube.com/watch?v=Yglf1EKBv2A)

---

# Operation

Drives are automatically mounted to:

`/run/media/deck/[LABEL]`

For example:

`/run/media/deck/External-ssd/`

If a device has no filesystem label, its UUID will be used instead.

For example:

`/run/media/deck/a12332-12bf-a33ab-eef/`

---

# Installation

## Via Curl (One-Line Install)

Open Konsole on your Steam Deck and run:

```bash
curl -sSL https://raw.githubusercontent.com/spydarek/Steam-Deck.Mount-External-Drive/main/curl_install.sh | bash
```

A `sudo` password is required.

If you have not set one yet, run:

```bash
passwd
```

Follow the on-screen instructions.

---

# Uninstall

To remove SDMED, run the following commands in Konsole:

```bash
sudo rm /etc/udev/rules.d/99-steamos-automount.rules

sudo rm /etc/systemd/system/external-drive-mount@.service

sudo rm -r /home/deck/.local/share/scawp/SDMED

sudo udevadm control --reload

sudo systemctl daemon-reload
```

---

# WORK IN PROGRESS!

This project may contain bugs, so use it at your own risk.

If you encounter any problems, please report them under:

[Issues](https://github.com/scawp/Steam-Deck.Mount-External-Drive/issues)

---

# Credits

Original project by [scawp](https://github.com/scawp).

exFAT automatic mount permission changes by [darekspy](https://github.com/spydarek).
