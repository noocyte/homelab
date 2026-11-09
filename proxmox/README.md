# Proxmox host (192.168.0.107, node `pve`)

Managed by hand. PVE 9.2.26, kernel 7.0.14-28-pve (updated 2026-11-09; notes
and checklists in issue #44). This file records what was set up, so it can be
done again on a fresh install. The nightly config tarball
(below) holds the exact files.

## Layout

| What | Details |
|---|---|
| ZFS pool `storage` | 4 disks, raidz1, mounted at `/storage`. Datasets `storage/immich` (zstd, atime off; sanoid snapshots), `storage/shares` (+ `media`) |
| `ssd-pool` | LVM-thin on the SSD: system disks of VM 102, VM 200, LXC 100 |
| Network | `vmbr0` on `nic0`, 192.168.0.107/24, gw .1 |
| NFS export | `/storage/shares/backups` → 192.168.0.0/24, `all_squash,anonuid=100000`. VM 200 mounts it as `/mnt/backups`; Home Assistant mounts its subfolder `homeassistant/` (HA → Settings → System → Storage, `NASBACKUP`) |
| NFS export | `/storage/shares/archive` → 192.168.0.0/24, same options. Desktop: `/var/mnt/bigarchive`; VM 200: `/mnt/archive` (read-only, for the Jotta backup) |
| virtiofs mappings | `immich-fs` → `/storage/immich` (VM 102, VM 200 read-only), `media-fs` → `/storage/shares/media` (VM 102) |
| GPU passthrough | IOMMU on by kernel default (cmdline is just `quiet`); vfio modules in `/etc/modules`. GTX 1060 bound to `vfio-pci` at boot (see below). VM 102 `hostpci0: 01:00` |
| Shutdown order | `pve-guests` starts after `nfs-server` (see below), so the guests stop before the NFS server does |
| sanoid | `storage/immich`: 48 hourly, 14 daily, 8 weekly, 3 monthly |
| VM 102 `plex-enc` | Ubuntu 24.04, Immich (`compose/immich/`) + Plex |
| LXC 100 `nas-server` | Debian 13, Samba (.220): shares `Shares`, `Media`, `Backups` (user `jarle`), `Cabin` (user `cabin`, see the main README) |
| VM 200 `docker-host` | Flatcar, rebuilt from this repo (see main README) |

## GPU passthrough and shutdown order

No NVIDIA driver on the host. The `.run`-installed 595 driver was removed on
2026-11-09: it can't drive Pascal cards anyway, and its DKMS build was a risk
on every kernel update. VM 102 has its own driver (580 branch).

```sh
cat > /etc/modprobe.d/vfio.conf <<'MODPROBE'
options vfio-pci ids=10de:1c02,10de:10f1
softdep nouveau pre: vfio-pci
softdep nova_core pre: vfio-pci
softdep nvidia pre: vfio-pci
softdep snd_hda_intel pre: vfio-pci
MODPROBE
cat > /etc/modprobe.d/blacklist-gpu-host.conf <<'MODPROBE'
blacklist nouveau
options nouveau modeset=0
blacklist nova_core
blacklist nvidia
blacklist nvidia_drm
blacklist nvidia_modeset
blacklist nvidia_uvm
blacklist nvidia_peermem
MODPROBE
update-initramfs -u -k all
# after boot: lspci -nnk -s 01:00  ->  "Kernel driver in use: vfio-pci" (both functions)
```

VM 200 mounts NFS exports from this host. Without the ordering below,
`nfs-server` stopped first on reboot, VM 200 hung unmounting its NFS mounts
and was hard-stopped after 180 s (seen 2026-11-09):

```sh
mkdir -p /etc/systemd/system/pve-guests.service.d
printf '[Unit]\nAfter=nfs-server.service\n' \
  > /etc/systemd/system/pve-guests.service.d/after-nfs-server.conf
systemctl daemon-reload
```

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

## Metrics: node-exporter (temperatures, ZFS, SMART)

Installed 2026-11-09, after the host update (on the un-updated host apt
wanted 14 core upgrades for it). VictoriaMetrics scrapes `:9100` as job
`proxmox-node`. Dashboards in Grafana → Proxmox: "Proxmox hardware:
temperatures and SMART" and "Node Exporter Full (pve)".

```sh
apt-get install --no-install-recommends \
  prometheus-node-exporter prometheus-node-exporter-collectors
# uses the smartmontools that PVE already has; skips ipmitool/nvme-cli/snmp
curl -s localhost:9100/metrics | grep -E '^(node_hwmon_temp_celsius|smartmon_device_smart_healthy)'
```

- `prometheus-node-exporter-smartmon.timer` (every 15 min) writes
  `/var/lib/prometheus/node-exporter/smartmon.prom`;
  `prometheus-node-exporter-apt.timer` writes pending updates and
  `node_reboot_required`.
- The HGST SAS disks report temperature, health and *grown defects* (their
  version of reallocated sectors) but no power-on hours. The SATA SSDs report
  the usual ATA attributes, including wear leveling.
- CPU temperatures come from `coretemp`. There is no hwmon sensor for the
  disks (SAS disks don't work with `drivetemp`), so disk temperatures come
  from SMART only. The GPU is passed through, so the host can't see its temperature.

## Logs → VictoriaLogs

Vector on the host forwards the systemd journal to Vector on docker-host
(`compose/victorialogs`), which puts it into the common log schema (`host`,
`service`, `level`, …). Config: `vector.yaml` in this folder. PVE 9 has no
rsyslog. Vector remembers its journal position and disk-buffers up to
256 MiB while docker-host is down.

```sh
curl -fLO https://packages.timber.io/vector/0.60.0/vector_0.60.0-1_amd64.deb
apt-get install -y ./vector_0.60.0-1_amd64.deb     # no repo added; pinned
cp vector.yaml /etc/vector/vector.yaml
systemctl enable --now vector
```

Query: `host:pve`, e.g. `host:pve service:pvedaemon.service`, `host:pve level:error`.

History: 2026-11-04 the journal went straight to VictoriaLogs with
`systemd-journal-upload` (package `systemd-journal-remote`); replaced by
Vector on 2026-11-05 so all sources share one schema.

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
- Fix (2026-11-03, on the VM only; the weekly image includes it):
  `/etc/apt/apt.conf.d/52homelab-auto-reboot` makes unattended-upgrades
  reboot at 04:00 UTC when a reboot is required. The NVIDIA packages don't
  flag that themselves, so the same file adds an apt hook that runs
  `/usr/local/sbin/nvidia-reboot-check`, which touches
  `/var/run/reboot-required` when `modinfo -F version nvidia` differs from
  the loaded module in `/proc/driver/nvidia/version`.
- Driver packages (2026-11-09): only the 580 branch (Pascal legacy) is
  installed. `nvidia-driver-550` had become a transitional package that pulled
  in 580, so 580 was marked "automatic": purging 550 would have made apt (and
  unattended-upgrades) treat the whole 580 driver as removable. Fixed with
  `apt-mark manual nvidia-driver-580` before `apt-get purge nvidia-driver-550
  nvidia-utils-550`. Before removing an old driver branch, run
  `apt-get -s purge ...` and check the "no longer required" list.
- GPU metrics (2026-11-09): `compose/gpu-exporter` runs as
  `/home/jarle/gpu-exporter/compose.yaml` on the VM (nvidia_gpu_exporter,
  `:9835`, VictoriaMetrics job `gpu`). Grafana → Proxmox: "Nvidia GPU (VM 102
  plex-enc)" and the GPU row in "Proxmox hardware". Its "GPU driver" panel
  turns red when `nvidia-smi` fails, so a driver mismatch like the one above is
  visible right away.
  **Not a Komodo stack** (Komodo doesn't manage this VM): merging a change,
  e.g. a Renovate image update, deploys nothing. Deploy by hand, on VM 102
  as `jarle`:
  ```sh
  cd ~/gpu-exporter
  curl -fsSLO https://raw.githubusercontent.com/noocyte/homelab/main/compose/gpu-exporter/compose.yaml
  docker compose up -d
  ```
