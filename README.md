# Homelab

GitOps for the home lab. **Git is the source of truth**: the VM's operating
system config, the deployment tool (Komodo) and every app stack live in this
repo. Secrets do not.

```
Proxmox (192.168.0.107, "pve")             ← managed by hand, NOT updated (NVIDIA)
 ├─ VM 102  plex-enc     Immich + Plex     ← not managed here (yet)
 ├─ LXC 100 nas-server   Samba (.220)      ← Home Assistant backups go through it
 └─ VM 200  docker-host  Flatcar (.240)    ← THIS REPO
     ├─ komodo.service   Komodo Core + Periphery (started by the OS)
     └─ Komodo stacks    everything in compose/ (deployed by Komodo from git)
```

| Path | What |
|---|---|
| `flatcar/docker-host.bu` | The VM's whole OS config (user, SSH key, mounts, Docker, Komodo) |
| `scripts/build-ignition.sh` | Turns the above into `build/docker-host.ign` (incl. secrets) |
| `komodo/compose.yaml` | Komodo itself |
| `komodo/sync/*.toml` | Which stacks exist, and how they are configured (Komodo "Resource Sync") |
| `compose/<app>/compose.yaml` | One folder per app |
| `secrets/`, `build/` | **Git-ignored.** Generated locally, contain passwords |

---

## Rebuilding the docker VM from scratch

The whole Proxmox host gone? Start with
[docs/disaster-recovery.md](docs/disaster-recovery.md); it tells you when to
come here.

Run on your desktop, in this repo, unless the step says *Proxmox shell*.

### 1. Build the Ignition config

```sh
scripts/build-ignition.sh
```

The first run creates `secrets/komodo.env` with random passwords and prints
the Komodo admin login. **Save the admin password in the password manager.**
Later runs reuse the same secrets. The output, `build/docker-host.ign`, is the
VM's config incl. secrets.

### 2. Copy it to Proxmox

```sh
scp build/docker-host.ign root@192.168.0.107:/var/lib/vz/snippets/docker-host.ign
```

### 3. Create the VM (*Proxmox shell*)

```sh
VM_ID=200
cd /var/lib/vz/import
wget -O flatcar.img https://stable.release.flatcar-linux.net/amd64-usr/current/flatcar_production_proxmoxve_image.img

qm create $VM_ID --name docker-host --onboot 1 \
  --bios ovmf --efidisk0 ssd-pool:1 \
  --machine q35 --args "-machine sata=off" \
  --cores 4 --memory 12288 --agent 1 \
  --net0 virtio,bridge=vmbr0 \
  --ipconfig0 ip=192.168.0.240/24,gw=192.168.0.1 --nameserver 1.1.1.1 \
  --virtio0 ssd-pool:0,import-from=/var/lib/vz/import/flatcar.img --boot order=virtio0 \
  --scsihw virtio-scsi-pci --scsi0 ssd-pool:cloudinit \
  --virtiofs0 immich-fs \
  --cicustom user=local:snippets/docker-host.ign

qm disk resize $VM_ID virtio0 128G
qm start $VM_ID
rm /var/lib/vz/import/flatcar.img
```

Notes:
- Ignition runs **once, on first boot**. To change OS config later: edit the
  `.bu` file, rebuild, and recreate the VM (data on `/srv` is on the VM disk,
  so restore it from backup, see below), or apply the change by hand and keep
  the `.bu` file in sync.
- Messages about cloud-init failing during boot are expected and harmless
  (Flatcar reads the same file with Ignition).
- The VM uses `1.1.1.1` for its own DNS on purpose, so it doesn't depend on
  the Pi-hole it runs.

### 4. Check the VM

```sh
ssh core@192.168.0.240
systemctl status komodo mnt-backups.mount mnt-immich.mount
docker ps
```

Komodo UI: **http://192.168.0.240:9120**. Log in as `admin`.

### 5. Connect Komodo to this repo (one time)

1. **Settings → Variables**: add every secret from the [table below](#secrets),
   each with **Secret** ticked.
2. **Syncs → New Resource Sync**, named `homelab`: repo `noocyte/homelab`,
   branch `main`, resource path `komodo/sync`. Save, then **Refresh** and
   **Execute**.

The sync creates all stacks and deploys those with `deploy = true`. From then
on the sync manages itself (`komodo/sync/sync.toml`).

### 6. Restore data

Each app keeps its data in `/srv/<app>` on the VM. Restore **before**
deploying the app, or stop it first.

| App | Restore from |
|---|---|
| backup | `rclone.conf` → `/srv/rclone/rclone.conf` (mode 600). The crypt password is in the password manager; the Jottacloud token can be recreated with `rclone config`. |
| trip-planner | a dated folder from `/mnt/backups/trip-planner/` → `/srv/trip-planner/storage/`, see `backup-db.py` |
| crafty | `/srv/crafty/` |
| teslamate | Postgres dump (`pg_dump`) → restore into the `database` service, see "Migrating TeslaMate" |

---

## Day to day

- **Change an app**: edit `compose/<app>/compose.yaml` (or its script), merge
  to `main`. Within 5 minutes the `homelab-gitops` procedure deploys the
  stacks whose files changed (`komodo/sync/procedures.toml`). It pauses
  02:00-03:59 so it can't interrupt the nightly dump and backup. To deploy
  right away: **Deploy** on the stack, or **Run** the procedure.
- **Add an app**: new folder in `compose/` and a `[[stack]]` entry in
  `komodo/sync/stacks.toml` with the `gitops` tag. Merge; the procedure
  syncs and deploys it.
- **Changed `komodo/sync/procedures.toml`?** The procedure can't update
  itself while it runs, so execute the `homelab` sync by hand once
  (Komodo → Syncs → homelab → Execute).
- **Is it working?** Komodo → Procedures → `homelab-gitops`: last run and its
  log. A failed run sends an alert.
- **OS updates**: automatic. Flatcar downloads updates and reboots in the
  04:30-05:30 window. A failed update rolls back by itself.
- **Logs / shell / container stats**: Komodo UI. In a terminal: `ssh core@192.168.0.240`,
  then `docker ...`, or `lazydocker`.

## Secrets

Stored as Komodo Variables (secret), used in `komodo/sync/stacks.toml` as
`[[NAME]]`. Keep a copy of each in the password manager.

| Variable | Used by |
|---|---|
| `PIHOLE_ADMIN_PASSWORD` | pihole |
| `CLOUDFLARE_API_TOKEN` | cloudflare-ddns (Zone DNS Edit + Account Filter Lists Edit) |
| `CLOUDFLARE_TUNNEL_TOKEN` | cloudflared |
| `ROUTER_GOOGLE_API_KEY`, `ROUTER_DATEX_USERNAME`, `ROUTER_DATEX_PASSWORD` | weatherrouter |
| `TESLAMATE_ENCRYPTION_KEY` | teslamate (**must** be the original key) |
| `TESLAMATE_DB_PASS` | teslamate |
| `TESLAMATE_TIBBER_TOKEN`, `TESLAMATE_ABRP_TOKEN` | teslamate |
| `TESLAMATE_SAIC_TOPIC_PREFIX`, `TESLAMATE_SAIC_DB_URI` | teslamate (saic2postgresql) |
| `UNPOLLER_UNIFI_PASS` | unpoller (UniFi local account `unpoller`, View Only) |

Not in Komodo: `secrets/komodo.env` (Komodo's own DB/admin/JWT secrets,
embedded in the Ignition file) and `/srv/rclone/rclone.conf`.

## Backups

Every service writes its own backups to **one place**: the ZFS share
`/storage/shares/backups` on Proxmox (raidz1), mounted on the docker VM as
`/mnt/backups` (NFS), one folder per service. At 03:00 the `backup` stack
mirrors each folder, encrypted, to Jottacloud `jottacrypt:<folder>`. History
lives in the folders themselves (dated files), so Jotta is a plain mirror.
Immich is the exception: its library and DB dumps are synced straight from
`storage/immich`.

| Folder (`/mnt/backups/…`) | What | Written by, when | Kept |
|---|---|---|---|
| `komodo/` | Komodo DB (users, API keys, secret variables) | Komodo's "Backup Core Database" procedure, 01:00 | Komodo's setting |
| `teslamate/` | `teslamate` + `mg_ismart`, `pg_dump -Fc` | `compose/teslamate/dump.sh`, 02:30 (UTC in names) | 14 days |
| `trip-planner/<date>/` | DB copy + attachments, assets, config | `compose/trip-planner/backup-db.py`, 02:45 | 14 days |
| `victoriametrics/latest/` | Full DB, incremental | `vmbackup` sidecar, 02:50 | latest only |
| `homeassistant/` | HA backups (encrypted by HA, ~1.5 GB each) | HA, ~05:30, over NFS (HA network storage `NASBACKUP`) | HA keeps 10 |
| `proxmox/dump/` | VM 102 + LXC 100 whole images (vzdump, zstd) | Proxmox backup job, Sun 01:00 | 2 per guest |
| `onedrive/<name>/` | personal OneDrive, one-way copy; deleted/changed files kept 30 days in `onedrive/.deleted/<date>/` | `compose/backup/onedrive.sh`, 02:00 | mirror of OneDrive |
| `proxmox/host/` | Proxmox host config | `proxmox/pve-config-backup.sh`, 01:30 | 14 days |
| *(Immich)* | library + Immich's DB dumps | Immich; synced from `/mnt/immich` | changed/deleted kept in `jottacrypt:archive/immich/<date>` |

All the jobs refuse to write if the share isn't mounted (nothing lands on
the VM's own disk), and `backup.sh` skips the mirror then, so an empty mount
can't wipe Jotta.

### OneDrive copies

`rclone-onedrive` (in the `backup` stack) copies every account in
`/srv/rclone-onedrive/rclone.conf` named `onedrive-<name>` to
`/mnt/backups/onedrive/<name>` at 02:00. Read-only towards OneDrive.
Accounts today: `onedrive-jarle` (~630 GB). Personal Vault is not copied
(locked; rclone can't read it).

Add an account (the owner logs in once):

1. On a desktop with a browser:
   `podman run --rm -it --network host docker.io/rclone/rclone:1 authorize onedrive`
   → log in to Microsoft in the browser → copy the token it prints
   (the `{"access_token":…}` line).
2. On the docker VM:
   `docker exec rclone-onedrive rclone config create onedrive-<name> onedrive token '<token>' drive_type personal drive_id <id> --non-interactive`.
   The drive id: `GET https://graph.microsoft.com/v1.0/me/drive` with the
   token's `access_token` as Bearer → `id`. Check with
   `docker exec rclone-onedrive rclone about onedrive-<name>:`.

The first copy of an account downloads everything and can take more than a
night; later runs copy only changes. If a login expires (unused for 90
days, or a password change), redo both steps.

**Keys needed to restore** (password manager): the rclone crypt password
*and* salt (`password`/`password2` in `rclone.conf`; without them nothing on
Jotta can be read) and Home Assistant's backup encryption key (HA →
Settings → System → Backups → emergency kit).

Not backed up: `/storage/shares/media`, `/storage/shares/public`,
`/storage/shares/backups/From NAS`. VM 200 (docker-host) is rebuilt from
this repo rather than imaged.

Bandwidth: both rclone containers are limited to 100 Mbit/s between 06:00
and 00:00 and run at full speed at night (`RCLONE_BWLIMIT` in
`compose/backup/compose.yaml`).

Scheduling is Ofelia (in the `backup` stack), driven by `ofelia.*` labels on
the containers.

Ofelia reads the labels only when it starts. Stacks with backup jobs
restart `backup-scheduler` after each deploy (`post_deploy` in
`komodo/sync/stacks.toml`). If you change `ofelia.*` labels some other way,
restart `backup-scheduler` yourself and check its log for
`New job registered`.

**Is a backup running?** `backup-scheduler` log: a `Started` line with no
`Finished` after it means yes. To be sure (also catches manual runs), run `ps`
in the `rclone-backup` terminal and look for `backup.sh` / `rclone sync`. Avoid
redeploying the backup stack between 02:30 and ~03:15.

**Restore TeslaMate** (tested 2026-11-02): start an empty `postgres:17`,
`createdb mg_ismart`, then `pg_restore -d teslamate <dump>` and
`pg_restore -d mg_ismart <dump>`.

## Ports on 192.168.0.240

| Port | App |
|---|---|
| 53 tcp/udp | Pi-hole DNS |
| 8080 | Pi-hole admin (`/admin`) |
| 9120 | Komodo |
| 8300 | trip-planner |
| 8200 | weatherrouter |
| 4000 / 3000 | TeslaMate / Grafana |
| 1883 | Mosquitto (MQTT) |
| 5000 | OSRM |
| 8428 | VictoriaMetrics (HA writes here, Grafana reads; web UI at `/vmui`) |
| 9130 | unpoller (`/metrics`, scraped by VictoriaMetrics) |
| 9617 | pihole-exporter (`/metrics`, scraped by VictoriaMetrics) |
| 8443, 8123, 19132/udp, 25500-25600 | Crafty / Minecraft (router port forwards point here) |

## Migrating TeslaMate (from serverlite)

The database is the valuable part. The data is copied, never moved: serverlite
stays untouched until the new instance is verified.

*Done 2026-11-02.* Kept for reference:

1. On serverlite: stop everything except the database
   (`docker compose stop teslamate teslamateagile abrp saic2postgresql grafana`).
2. Dump both databases: `pg_dump -Fc` of `teslamate` and `mg_ismart`.
3. Copy the dumps to the new VM and check their checksums.
4. On the new VM: start only `database`, restore both dumps, compare row counts
   with serverlite.
5. Copy `osrm-data` (or run `osrm-setup.sh`), and the mosquitto config.
6. Set `deploy = true` for teslamate in `komodo/sync/stacks.toml`, push,
   execute the sync, and check the TeslaMate UI and Grafana.
7. Only then stop TeslaMate on serverlite.

## Home Assistant history (VictoriaMetrics)

HA keeps detailed history for 10 days. Numbers we want for years (energy,
temperatures) also go to VictoriaMetrics (`compose/victoriametrics`), which
keeps them forever. Grafana reads them through the `VictoriaMetrics` data
source.

HA side, in `configuration.yaml` on the HA box (not managed from this repo).
HA's built-in InfluxDB integration, v1 API - VictoriaMetrics accepts it:

```yaml
influxdb:
  api_version: 1
  host: 192.168.0.240
  port: 8428
  database: homeassistant
  # Metric names like sensor__temperature_value / sensor__energy_value,
  # with an entity_id label - easy to query in Grafana.
  measurement_attr: domain__device_class
  include:
    domains:
      - sensor
```

HA also sends every attribute as its own series; `relabel.yml` drops all but
the `*_value` series on arrival.

Restart HA, then check in VictoriaMetrics' UI (`http://192.168.0.240:8428/vmui`)
with the query `{entity_id=~".+"}`. Only numeric values are stored; text
states and text attributes are dropped.

Restore: `vmrestore` from `/mnt/backups/victoriametrics/latest` (or its copy
in `jottacrypt:victoriametrics`), see `compose/victoriametrics/compose.yaml`.

## UniFi statistics (unpoller)

`compose/unpoller` reads the UniFi controller (UDR Ultra, 192.168.0.1) with
a read-only account and exposes the numbers on `:9130/metrics`.
VictoriaMetrics scrapes them every 30 s (`compose/victoriametrics/scrape.yml`)
and keeps them with the rest. Dashboards: Grafana folder **UniFi**, from
UnPoller's official set (grafana.com 11311-11315), in
`compose/teslamate/grafana/dashboards/unifi/`.

UniFi account: UniFi → Admins & Users → Create New Admin → "Restrict to
local access only", username `unpoller`, role **View Only** for Network.
Its password is the Komodo secret `UNPOLLER_UNIFI_PASS`.

## Not managed here (yet)

- `compose/immich/` runs on VM 102 (`plex-enc`), deployed by hand.
- Proxmox host: set up by hand; what was changed, and its backups, are in
  `proxmox/README.md`. UniFi (see issue #7).
