# Homelab

GitOps for the home lab. **Git is the source of truth**: the VM's operating
system config, the deployment tool (Komodo) and every app stack live in this
repo. Secrets do not.

```
Proxmox (192.168.0.107, "pve")             ← managed by hand, NOT updated (NVIDIA)
 ├─ VM 102  plex-enc     Immich + Plex     ← not managed here (yet)
 ├─ LXC 100 nas-server   Samba (.220)      ← file shares for PCs
 │  (pve itself exports /storage/shares/backups over NFS: docker-host, HA)
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
| crafty | newest `/mnt/backups/crafty/nightly/crafty-<date>.tar.gz` → `/srv/crafty`, see `compose/crafty/backup.py` |
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
- **Image updates**: Renovate opens a PR per update (`renovate.json5`), see
  [Image updates (Renovate)](#image-updates-renovate). Merge them one at a time.
- **OS updates**: automatic. Flatcar downloads updates and reboots in the
  04:30-05:30 window. A failed update rolls back by itself.
- **Logs / shell / container stats**: Komodo UI. In a terminal: `ssh core@192.168.0.240`,
  then `docker ...`, or `lazydocker`.

## Image updates (Renovate)

The Mend-hosted **Renovate** GitHub app (free) reads every `image:` in
`compose/*/compose.yaml` and `komodo/compose.yaml` and opens a PR when a newer
image exists. Rules are in `renovate.json5`:

- A release has to be **14 days old** before its PR appears. Exception:
  ghcr.io and registry.gitlab.com give Renovate no release dates, so those
  PRs come at once with the label **`check release age`**. Look at the
  release date (and release notes) before merging.
- **Major versions** (Postgres 17 → 18, Mosquitto 1.6 → 2, ...) only appear
  after ticking them in the **Dependency Dashboard** issue.
- Moving tags (`postgres:17`, `rclone:1`, ...) are pinned to a digest, so a
  rebuilt tag becomes a PR too instead of changing on the next pull.
- At most 3 open PRs. **Merge one at a time** and let Komodo deploy it:
  several stacks deploying at once crash-looped `backup-scheduler` before.
- `komodo` PRs (label **`manual deploy`**): Komodo doesn't deploy itself;
  deploy on docker-host by hand.
- Not covered: Immich (`IMMICH_VERSION` pinned in `compose/immich/example.env`; other VM, see `compose/immich/README.md`), FerretDB/DocumentDB
  (versions tied to Komodo), our own `noocyte/*:latest` images, images
  pinned by digest only (osrm), Vector on pve/HA, the Grafana plugin version.

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
| `PVE_EXPORTER_TOKEN` | pve-exporter (Proxmox API token `prometheus@pve!exporter`, PVEAuditor - read-only) |
| `HA_BACKUP_WEBHOOK` | backup (`backup-status.sh` → HA automation "Backup status"; `http://192.168.0.63:8123/api/webhook/<id>`) |

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
| `homeassistant-cabin/` | the cabin's Home Assistant backups (encrypted by HA, ~13 MB) | cabin HA, ~05:00, over Tailscale → Samba share `Cabin` (see Remote access) | HA's setting |
| `onedrive/jarle/Apps/Home Assistant/backups_3bf5b0b4/` | second copy of the cabin's HA backups (HA also uploads them to jarle's OneDrive) | cabin HA → OneDrive; reaches us with the 02:00 copy | HA's setting, + 30 days in `.deleted/` |
| `crafty/nightly/` | Crafty DB + config + all Minecraft servers | `compose/crafty/backup.py`, 02:40 | 14 days |
| `crafty/server-backups/` | Crafty's own per-server backups | Crafty's UI | Crafty's setting |
| `proxmox/host/` | Proxmox host config | `proxmox/pve-config-backup.sh`, 01:30 | 14 days |
| *(archive)* | `/storage/shares/archive`: personal archive from the old NAS (KNX project, code, old configs) | by hand | changed/deleted kept in `jottacrypt:archive/personal-archive/<date>` |
| *(Immich)* | library + Immich's DB dumps | Immich; synced from `/mnt/immich` | changed/deleted kept in `jottacrypt:archive/immich/<date>` |

All the jobs refuse to write if the share isn't mounted (nothing lands on
the VM's own disk), and `backup.sh` skips the mirror then, so an empty mount
can't wipe Jotta.

### Backup status and alerts

`compose/backup/backup-status.sh` runs every 15 min (Ofelia, in
`rclone-backup`). It finds the newest backup of each job in the table above,
and reads when each folder last reached Jotta (`backup.sh` writes
`/srv/rclone/status/offsite-<folder>` after a good sync; `onedrive.sh` writes
`onedrive/.status-<name>`). A backup is **late** when its newest file is
older than its interval + 4 h (daily 28 h, cabin HA via OneDrive 52 h, vzdump 7 d 4 h); off-site when a
folder hasn't reached Jotta for 36 h.

- **Grafana → Backups**: status table per job, off-site table, sizes over time
  (numbers pushed to VictoriaMetrics as `backup_*`).
- **Home Assistant**: automation "Backup status" (webhook). Every run sets
  `input_text.backup_status` ("All 9 OK" / "1 of 9 late: crafty") and
  `input_datetime.backup_status_last_report`; a backup turning late, and
  recovering, sends a phone notification once. If no report arrives for 2 h,
  HA sends "Backup monitor silent".
- The webhook URL is the Komodo secret `HA_BACKUP_WEBHOOK`
  (`http://192.168.0.63:8123/api/webhook/<id>`, local only; the id is in the
  HA automation's webhook trigger).

### OneDrive copies

`rclone-onedrive` (in the `backup` stack) copies every account in
`/srv/rclone-onedrive/rclone.conf` named `onedrive-<name>` to
`/mnt/backups/onedrive/<name>` at 02:00. Read-only towards OneDrive.
Accounts today: `onedrive-jarle` (~630 GB). Personal Vault is not copied
(locked; rclone can't read it).

After a good copy, `onedrive.sh` measures it (exact `du`, ~3.5 min over
NFS) and asks OneDrive how much it holds (`rclone about`, 3 s), and writes
both to `onedrive/.size-<name>`. Grafana shows them as "Newest size" (the
copy), "Folder total" (copy + `.deleted/`) and "In source". OneDrive's
number is a few % higher (Personal Vault, version history); if the gap
grows, the copy is falling behind.

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
`/storage/shares/rips` (DVD images), `/storage/shares/emu` (games). VM 200 (docker-host) is rebuilt from
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
| 9428 | VictoriaLogs (central logs; web UI at `/select/vmui`, kept 30 days, no backup) |
| 5514/udp | Syslog into Vector → VictoriaLogs (UniFi) |
| 6000 | Vector protocol: journals from Vector on pve and on Home Assistant OS |
| 9130 | unpoller (`/metrics`, scraped by VictoriaMetrics) |
| 9617 | pihole-exporter (`/metrics`, scraped by VictoriaMetrics) |
| 9221 | pve-exporter (`/pve?target=192.168.0.107`, scraped by VictoriaMetrics) |
| 41641/udp | Tailscale (host network) |
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

Dashboards from this data: Grafana folder **Energy**
(`compose/teslamate/grafana/dashboards/energy/`) - *Now* (live power, today,
capacity tariff), *Consumption vs weather* (daily kWh vs outdoor temperature,
heating curve) and *Price and cost* (per month, paid vs average price, hour
of day). They use the HA entity ids (Tibber `*_torvmyrvegen_20`, Nord Pool
NO2, Easee, `utetemperatur`); renaming those in HA breaks the panels. Costs
are Tibber's energy cost - grid tariff (nettleie) is not included.

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

## Central logs (VictoriaLogs)

`compose/victorialogs`: VictoriaLogs keeps 30 days (max 15 GiB, no backup).
Query in vmui (http://192.168.0.240:9428/select/vmui) or Grafana → Explore →
**VictoriaLogs**. Pick a long enough time range: quiet services (Pi-hole) only
log on start/reload.

Everything goes through Vector (`compose/victorialogs/vector.yaml`), which
gives all sources one schema:

| Field | Values |
|---|---|
| `host` (stream) | `docker-host`, `pve`, `homeassistant`, `UCGULT` |
| `service` (stream) | compose project, container or systemd unit, syslog app (`unifi` for UniFi events) |
| `container` (stream) | container name (docker-host; HA OS core/Supervisor/add-ons) |
| `level` | `debug` `info` `notice` `warning` `error` `critical` `unknown` |
| `source` | `docker`, `journald`, `syslog` |

`level` comes from journald priority / syslog severity (not for containers:
Docker's journald driver only knows stdout/stderr), otherwise from the
text (JSON `level`, `level=`, `INFO`/`[ERROR]`/`▶ NOTICE`, `info:`, `[info]`,
Postgres `LOG:`). HA Core's multi-line entries (tracebacks) are merged back
into one log line. Blank lines are dropped.
Komodo's routine database chatter (ferretdb "Command handled … ok", postgres
"cron job …", ~19k lines/hour) is dropped.

| Source | How | Example query |
|---|---|---|
| Containers on docker-host | Vector, Docker API | `service:pihole`, `level:error` |
| Proxmox host | Vector on pve, journal → 6000/tcp (see `proxmox/README.md`) | `host:pve service:pvedaemon.service` |
| Home Assistant OS | Vector add-on, journal → 6000/tcp (see below) | `service:homeassistant level:error`, `service:hassio_supervisor` |
| UniFi (UCG Ultra) | syslog (CEF) → 5514/udp | `service:unifi`, `event:"Wired Client Disconnected"` |

UniFi setting (Network 10.6): Settings → **CyberSecure → Traffic Logging** →
Activity Logging (Syslog) = **SIEM Server**, `192.168.0.240` port `5514`.
Contents: all except "Firewall Default Policy" (very noisy). Debug Logs and
Netconsole off. Set 2026-11-05.

UniFi sends CEF. Vector (`compose/victorialogs/vector.yaml`) unpacks it: the
readable text becomes the message, the event name goes to `event`, and all
details to `unifi.*` (e.g. `unifi.UNIFIclientAlias:"Google Streamer 4K"`).
The time comes from UniFi's own UTC field.

Home Assistant OS has no package manager, so Vector runs as twiebe's
community add-on (<https://github.com/twiebe/hassos-addons>, Vector 0.60.0).
It reads the whole HA OS journal (Core, Supervisor, every add-on, the host)
and runs our own `homeassistant/vector.yaml` (option **Override Config** on;
the file goes in `/addon_configs/<repo>_vector/vector.yaml`, e.g. with the
SSH add-on). Like pve it only forwards; the schema is applied on docker-host.
Auto-update is off for the add-on: it is a one-person project with a
prebuilt image, so update it deliberately.

## Remote access (Tailscale)

`compose/tailscale` makes the docker VM a Tailscale **subnet router** for
`192.168.0.0/24` (reach anything on the LAN from a tailnet device) and an
**exit node** (send a phone's/laptop's internet traffic out through home).
IPv4 only - the LAN has no public IPv6.

Set up once, by the tailnet owner:

1. First start: `docker logs tailscale` shows a `https://login.tailscale.com/…`
   link - open it and log in. The login is kept in `/srv/tailscale`.
2. Admin console → Machines → `docker-host`: **Edit route settings** →
   approve `192.168.0.0/24` and "Use as exit node"; **⋯ → Disable key expiry**.
3. Admin console → DNS → split DNS `home.lan` → `192.168.0.240` (Pi-hole), so
   `*.home.lan` names work over Tailscale.

No router port forward is needed (NAT traversal).

**Samba forward for the cabin.** `compose/tailscale/serve/serve.json`
forwards docker-host's Tailscale address `100.82.192.66:445` to the NAS's
Samba (`192.168.0.220:445`). The cabin's Home Assistant backs up there
**without** accepting the `192.168.0.0/24` route, so an overlapping cabin
LAN can't break its local devices. The port exists only on the tailnet
address; the Tailscale ACL limits the cabin node to it, and a Samba user of
its own limits it to its folder (NFS has no login, so not NFS).
containerboot re-reads the file when it changes, without a restart.

Set up for the cabin (by hand, outside git):

- NAS (LXC 100): Samba user `cabin` (system user, no login) and share
  `Cabin` → `/mnt/shares/backups/homeassistant-cabin` (`valid users = cabin`,
  `hosts allow = 192.168.0.240`, hidden). Password in the password manager.
- Tailscale policy (admin console): `tag:cabin` may reach only
  `docker-host:445`; our own devices (`autogroup:member`) everything. The
  policy's `tests` check this on every save.
- Cabin HA, Tailscale app: `advertise_tags: [tag:cabin]`, `accept_routes`
  and `accept_dns` off, `userspace_networking` off. Network storage (Backup):
  Samba, server `100.82.192.66`, share `Cabin`, user `cabin`. Backup
  locations: this + OneDrive.

## Not managed here (yet)

- `compose/immich/` runs on VM 102 (`plex-enc`), deployed by hand.
- Proxmox host: set up by hand; what was changed, and its backups, are in
  `proxmox/README.md`. UniFi (see issue #7).
