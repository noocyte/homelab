#!/bin/sh
# Nightly copy of the Proxmox host's own configuration - the part a vzdump
# image doesn't cover. Restoring a dead host = reinstall Proxmox, then use
# this tarball as the reference (see docs/disaster-recovery.md).
#
# Installed by hand on the host:
#   /usr/local/sbin/pve-config-backup.sh
#   /etc/cron.d/pve-config-backup  (01:30 daily)
# Output: /storage/shares/backups/proxmox/host/pve-host-<date>.tar.gz, 14 kept.
# The docker-host backup job copies the folder to Jotta (encrypted) at 03:00.
#
# Contains secrets (/etc/pve private keys, root's SSH keys). The files are
# mode 600, owned by 100000 - the uid the NFS export squashes to, so the
# docker-host backup job can read them. They leave the host only encrypted.
set -eu

OUT=/storage/shares/backups/proxmox/host
KEEP=14
DATE="$(date +%F)"

# Refuse to write into the root disk if the ZFS share isn't mounted.
mountpoint -q /storage/shares || { echo "/storage/shares not mounted" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
S="$TMP/pve-host-$DATE"
mkdir -p "$S/state"

# Config files. /etc/pve is pmxcfs (FUSE); copy it to a normal folder first.
cp -a /etc/pve "$S/etc-pve"
tar -cf - --ignore-failed-read \
  /etc/network /etc/hosts /etc/hostname /etc/resolv.conf /etc/fstab \
  /etc/modprobe.d /etc/modules /etc/modules-load.d /etc/kernel/cmdline \
  /etc/default/grub /etc/exports /etc/sanoid /etc/vzdump.conf \
  /etc/cron.d /etc/apt/sources.list /etc/apt/sources.list.d \
  /etc/ssh/sshd_config /root/.ssh /etc/systemd/system \
  /usr/local/sbin 2>/dev/null | tar -xf - -C "$S"

# State that only exists as command output.
cd "$S/state"
pveversion -v                         > pveversion.txt
cat /proc/cmdline                     > proc-cmdline.txt
uname -a                              > uname.txt
lspci -nnk                            > lspci.txt
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL,SERIAL > lsblk.txt
ls -l /dev/disk/by-id                 > disk-by-id.txt
zpool status                          > zpool-status.txt
zpool get all                         > zpool-props.txt
zfs list -o name,used,avail,mountpoint,compression,recordsize,atime > zfs-list.txt
zfs get -s local all                  > zfs-local-props.txt
{ pvs; vgs; lvs; }                    > lvm.txt 2>&1 || true
pvesm status                          > pvesm-status.txt
qm list                               > qm-list.txt
pct list                              > pct-list.txt
dpkg --get-selections                 > dpkg-selections.txt
ip -br addr                           > ip-addr.txt
nvidia-smi -L                         > nvidia.txt 2>&1 || true

tar -czf "$OUT/pve-host-$DATE.tar.gz.part" -C "$TMP" "pve-host-$DATE"
chmod 600 "$OUT/pve-host-$DATE.tar.gz.part"
chown 100000:100000 "$OUT/pve-host-$DATE.tar.gz.part"
mv "$OUT/pve-host-$DATE.tar.gz.part" "$OUT/pve-host-$DATE.tar.gz"

# Keep the newest $KEEP.
ls -1t "$OUT"/pve-host-*.tar.gz | tail -n +$((KEEP + 1)) | xargs -r rm -f
echo "wrote $OUT/pve-host-$DATE.tar.gz ($(du -h "$OUT/pve-host-$DATE.tar.gz" | cut -f1))"
