# Proxmox host (192.168.0.107, node `pve`)

Managed by hand - **not updated** (PVE 9.2.3, kernel 7.0.6-2-pve; an update
once broke the NVIDIA passthrough for VM 102). This file records what was set
up, so it can be done again on a fresh install. The nightly config tarball
(below) holds the exact files.

## Layout

| What | Details |
|---|---|
| ZFS pool `storage` | 4 disks, raidz1, mounted at `/storage`. Datasets `storage/immich` (zstd, atime off; sanoid snapshots), `storage/shares` (+ `media`) |
| `ssd-pool` | LVM-thin on the SSD: system disks of VM 102, VM 200, LXC 100 |
| Network | `vmbr0` on `nic0`, 192.168.0.107/24, gw .1 |
| NFS export | `/storage/shares/backups` → 192.168.0.0/24, `all_squash,anonuid=100000` (VM 200 mounts it as `/mnt/bigbackup`) |
| virtiofs mappings | `immich-fs` → `/storage/immich` (VM 102, VM 200 read-only), `media-fs` → `/storage/shares/media` (VM 102) |
| GPU passthrough | kernel cmdline `intel_iommu=on iommu=pt`; vfio modules in `/etc/modules`; nouveau/nvidiafb blacklisted. VM 102 `hostpci0: 01:00` |
| sanoid | `storage/immich`: 48 hourly, 14 daily, 8 weekly, 3 monthly |
| VM 102 `plex-enc` | Ubuntu 24.04, Immich (`compose/immich/`) + Plex |
| LXC 100 `nas-server` | Debian 13, Samba (.220): shares `Shares`, `Media`, `Backups`, user `jarle`. Home Assistant writes its backups here |
| VM 200 `docker-host` | Flatcar, rebuilt from this repo (see main README) |

## Backups of the host and its guests

Set up 2026-11-03:

```sh
# Backup storage: a folder on the ZFS share (vzdump puts images in dump/)
mkdir -p /storage/shares/backups/proxmox/host
chown 100000:100000 /storage/shares/backups/proxmox /storage/shares/backups/proxmox/host
pvesm add dir backups-proxmox --path /storage/shares/backups/proxmox \
  --content backup --prune-backups keep-last=2 --is_mountpoint /storage/shares --shared 0

# Weekly images of LXC 100 + VM 102 (Datacenter → Backup)
pvesh create /cluster/backup --schedule "sun 01:00" --vmid 100,102 \
  --storage backups-proxmox --mode snapshot --compress zstd \
  --prune-backups keep-last=2 --enabled 1

# Nightly host config tarball
cp pve-config-backup.sh /usr/local/sbin/ && chmod 755 /usr/local/sbin/pve-config-backup.sh
cat > /etc/cron.d/pve-config-backup <<'EOF'
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
30 1 * * * root /usr/local/sbin/pve-config-backup.sh >/var/log/pve-config-backup.log 2>&1
EOF
```

The docker-host `backup` stack copies `/storage/shares/backups/proxmox` to
Jottacloud (`jottacrypt:proxmox`) every night at 03:00.

## VM 102 notes

- `qemu-guest-agent` runs inside the VM (installed 2026-11-03), so backups
  freeze the filesystem for a consistent image, and `qm guest exec 102 -- ...`
  works from the host.
- The disk has `discard=on,ssd=1` (since 2026-11-03), and Ubuntu's weekly
  `fstrim.timer` hands deleted blocks back to the thin pool. Without it the
  disk filled up with deleted data (97% allocated, 25 GB used) and the
  vzdump image was 101 GB.
- Ubuntu's unattended upgrades update the NVIDIA libraries but the kernel
  module only changes on reboot. Until then the GPU is unusable
  (`nvidia-smi`: "Driver/library version mismatch"); this took Plex down
  from 2026-07-24 until the reboot on 2026-11-03. If Plex or Immich ML acts
  up: check `nvidia-smi`, reboot the VM.
- Fix (2026-11-03), files in `vm102/`: unattended-upgrades reboots the VM at
  04:00 UTC when a reboot is required (`52homelab-auto-reboot` →
  `/etc/apt/apt.conf.d/`). The NVIDIA packages don't flag that themselves,
  so an apt hook runs `nvidia-reboot-check` (→ `/usr/local/sbin/`), which
  flags it when the driver on disk differs from the loaded module.
