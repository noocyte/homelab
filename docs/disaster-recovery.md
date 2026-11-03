# Disaster recovery: the Proxmox host is gone

The order to rebuild everything that runs on the Proxmox host (192.168.0.107).
Home Assistant (192.168.0.63) is a separate box and keeps running; it only
loses its backup target until the NFS share is back.

**Restore status** (update when tested):

| Item | Restore tested? |
|---|---|
| TeslaMate (`pg_restore`) | ✅ 2026-11-02 (migration from serverlite) |
| VictoriaMetrics (`vmrestore`) | ✅ 2026-11-03, same point count as live |
| Trip planner (dated folder) | ❌ |
| Komodo DB (`km database restore`) | ❌ |
| LXC 100 / VM 102 (vzdump) | ❌ |
| Immich (library + DB dump) | ❌ |
| Proxmox host from scratch | ❌ |

---

## 0. What you need that isn't in the homelab

Keep these in the password manager. Without the first one, nothing in
Jottacloud can be read.

| What | Why |
|---|---|
| rclone crypt password for `jottacrypt` | Decrypts everything in Jotta. One password, no salt. |
| rclone crypt settings: `remote = jotta:backups`, `filename_encoding = base32768`, name/dir encryption on (defaults) | Wrong settings = files look missing |
| Jottacloud login | Re-create the `jotta` remote's token (`rclone config`) |
| Home Assistant backup encryption key (emergency kit) | Only if the HA box also has to be restored |
| `secrets/komodo.env` from the desktop | Rebuilding the docker VM with the same Komodo secrets. If lost, `scripts/build-ignition.sh` makes new ones; the Komodo DB restore brings users and variables back |
| GitHub access to `noocyte/homelab` | Everything in this repo |

The rclone config, written from those values:

```ini
[jotta]
type = jottacloud
# filled in by `rclone config reconnect jotta:` (Jottacloud login)

[jottacrypt]
type = crypt
remote = jotta:backups
filename_encoding = base32768
password = <rclone obscure 'the password from the password manager'>
```

## 1. Which situation are you in?

- **A. The SSD or the OS died, the four ZFS disks are fine.** All local
  backups are still on the pool (`/storage/shares/backups`). Nothing needs
  downloading; skip every "B only" step.
- **B. Everything is gone** (new hardware or new disks). All data comes
  from Jottacloud. The Immich library is ~500 GB: start that download
  early, it takes days.

Folders on the ZFS share, and where they are in Jotta:

| `/storage/shares/backups/…` | Jotta | Restores |
|---|---|---|
| `proxmox/host/` | `jottacrypt:proxmox/host` | Proxmox host config (step 3) |
| `proxmox/dump/` | `jottacrypt:proxmox/dump` | LXC 100, VM 102 (step 4) |
| `komodo/`, `teslamate/`, `trip-planner/`, `victoriametrics/` | `jottacrypt:<same name>` | docker VM apps (step 6) |
| `homeassistant/` | `jottacrypt:homeassistant` | Home Assistant (step 7) |
| *(storage/immich)* | `jottacrypt:immich` | Immich library + DB dumps (step 5) |

## 2. Install Proxmox

1. Install Proxmox VE 9 on the SSD. Hostname `pve`, IP `192.168.0.107/24`,
   gateway `192.168.0.1`. The installer creates the bridge `vmbr0`.
   *Do not run updates beyond what's needed* - see `proxmox/README.md`
   (NVIDIA passthrough).
2. SSD storage for guest disks (the installer's `local-lvm` is on the OS
   part; the guests live on `ssd-pool`). If the SSD is separate from the OS
   disk:
   ```sh
   pvcreate /dev/<ssd>; vgcreate ssd-pool /dev/<ssd>
   lvcreate -l 95%FREE --thinpool ssd-pool ssd-pool
   pvesm add lvmthin ssd-pool --vgname ssd-pool --thinpool ssd-pool --content images,rootdir
   ```
3. ZFS pool:
   - **A:** `zpool import -f storage`
   - **B:** create it (4 disks, raidz1), then the datasets. Exact settings
     are in the host tarball, `state/zfs-local-props.txt`:
     ```sh
     zpool create -o ashift=12 -m /storage storage raidz1 /dev/disk/by-id/<4 disks>
     zfs set compression=on storage
     zfs create -o compression=zstd -o atime=off storage/immich
     for d in library backups encoded-video profile thumbs; do zfs create storage/immich/$d; done
     zfs create storage/shares; zfs create storage/shares/media
     mkdir -p /storage/shares/backups /storage/shares/public
     chown -R 100000:100000 /storage/shares
     ```
   Then: `pvesm add zfspool storage --pool storage --content images,rootdir --mountpoint /storage`

## 3. Host configuration

1. Get the newest host tarball:
   - **A:** `/storage/shares/backups/proxmox/host/pve-host-<date>.tar.gz`
   - **B:** `apt install rclone`, write `~/.config/rclone/rclone.conf` (step 0),
     `rclone config reconnect jotta:`, then
     `rclone copy jottacrypt:proxmox /storage/shares/backups/proxmox --progress`
     (this also brings the VM images for step 4).
2. Unpack it somewhere (`tar -xzf … -C /root`) and re-apply by comparing,
   not by copying `/etc/pve` back wholesale:
   - GPU passthrough: kernel cmdline `intel_iommu=on iommu=pt`
     (`etc/kernel/cmdline` → `proxmox-boot-tool refresh`, or
     `etc/default/grub` → `update-grub`), `etc/modules` (vfio),
     `etc/modprobe.d/` (nouveau/nvidiafb blacklist, ZFS ARC limit).
   - NFS: `apt install nfs-kernel-server`, copy `etc/exports`, `exportfs -ra`.
   - virtiofs mappings (see `etc-pve/mapping/directory.cfg`):
     ```sh
     pvesh create /cluster/mapping/dir --id immich-fs --map node=pve,path=/storage/immich
     pvesh create /cluster/mapping/dir --id media-fs  --map node=pve,path=/storage/shares/media
     ```
   - ZFS snapshots: `apt install sanoid`, copy `etc/sanoid/sanoid.conf`.
   - Root's SSH `authorized_keys` from `root/.ssh/`.
   - Reboot. Check `lspci -nnk` against `state/lspci.txt` (GPU bound to vfio).
3. Backups of the host itself: run the commands under "Backups of the host
   and its guests" in `proxmox/README.md` (storage, weekly job, cron).

## 4. LXC 100 and VM 102

From `/storage/shares/backups/proxmox/dump/` (newest of each):

```sh
pct restore 100 vzdump-lxc-100-<date>.tar.zst --storage ssd-pool
qmrestore vzdump-qemu-102-<date>.vma.zst 102 --storage ssd-pool
```

- New hardware: the GPU may have another PCI address. `lspci | grep -i nvidia`,
  then `qm set 102 --hostpci0 <address>,pcie=1`.
- **B:** don't start VM 102 before step 5 has the Immich library in place.
- Start both. LXC 100 (Samba, .220) needs nothing else.
- VM 102: Plex comes back as it was in the image. Check `nvidia-smi` in the VM.

## 5. Immich (B only)

1. `rclone copy jottacrypt:immich /storage/immich --progress` (days).
   Thumbnails and encoded videos aren't backed up; Immich regenerates them
   (Administration → Jobs).
2. Start VM 102. Its image has Immich's database as of the image's date
   (≤ 7 days old). If photos were added after that, restore the newest dump
   from `/storage/immich/backups/` (`immich-db-backup-*.sql.gz`) following
   Immich's docs, "Backup and Restore" → "Manual restore", for the
   version in the file name.

## 6. Docker VM (VM 200)

Follow the main README, "Rebuilding the docker VM from scratch", **steps 1-4
only**, then come back here. App data must be in place before Komodo
deploys the apps.

1. rclone config: `/srv/rclone/rclone.conf` (mode 600), from the password
   manager (step 0).
2. **B only:** fill the share from Jotta (ZFS share is empty):
   ```sh
   for d in komodo teslamate trip-planner victoriametrics homeassistant; do
     docker run --rm -v /srv/rclone:/config -e RCLONE_CONFIG=/config/rclone.conf \
       -v /mnt/backups:/backups rclone/rclone:1 copy jottacrypt:$d /backups/$d --progress
   done
   ```
3. App data into `/srv` (newest backup of each, from `/mnt/backups/…`):
   - **TeslaMate:** start only the database, then restore both dumps - see
     "Restore TeslaMate" in the README. `TESLAMATE_ENCRYPTION_KEY` must be
     the original.
   - **Trip planner:** copy the newest `trip-planner/<date>/` into
     `/srv/trip-planner/storage/`, rename `trip.sqlite.backup` to
     `trip.sqlite`.
   - **VictoriaMetrics:**
     ```sh
     docker run --rm -v /srv/victoriametrics:/storage -v /mnt/backups/victoriametrics:/backups \
       victoriametrics/vmrestore:v1.155.0 -src=fs:///backups/latest -storageDataPath=/storage
     ```
   - Pi-hole, cloudflared, weatherrouter, unpoller: nothing - config is in
     git, secrets in Komodo.
4. Komodo: restore its database (users, API keys, secret variables, the
   `homelab` sync and procedures):
   ```sh
   docker exec -it komodo-core-1 km database restore   # newest folder in /mnt/backups/komodo
   sudo systemctl restart komodo
   ```
   Then **Syncs → homelab → Execute**. The sync deploys every stack with
   `deploy = true`; from then on `homelab-gitops` runs every 5 minutes.
   (If the Komodo backup is unusable: README step 5 instead, and enter every
   secret from the password manager.)

## 7. Home Assistant

Nothing to do if only Proxmox died: HA's network storage `NASBACKUP`
(NFS → `homeassistant/`) reconnects once the share is back. Check under
Settings → System → Storage.

If the HA box must be restored too: install HA OS, choose "Restore from
backup" during onboarding, upload the newest
`homeassistant/automatic_backup_*.tar`, and enter the backup key from the
emergency kit. (HA also keeps copies in Nabu Casa cloud and OneDrive.)

## 8. Check

- Proxmox: `pvesm status`, `qm list`, `pct list`, `zpool status`.
- Immich (VM 102 :2283) and Plex (:32400) answer; `nvidia-smi` in VM 102.
- Docker VM: Komodo → all stacks running; TeslaMate shows history;
  Grafana dashboards have data back to 2024.
- The next morning: `backup-scheduler` log shows every nightly job
  finished, and Jotta got fresh copies.

## Not recoverable

Not backed up anywhere off-site: `/storage/shares/media` (Plex library),
`/storage/shares/public`, `/storage/shares/rips` and `/storage/shares/emu`.
The personal archive (`/storage/shares/archive`) comes back with
`rclone copy jottacrypt:personal-archive /storage/shares/archive`.
