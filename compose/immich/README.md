# Immich (VM 102 `plex-enc`, 192.168.0.52:2283)

**Not a Komodo stack.** Runs on VM 102 from `/home/jarle/immich-app`
(`docker-compose.yml`, `hwaccel.*.yml`, `.env`), deployed by hand. Merging a
change here deploys nothing.

- `compose.yaml`: the official `docker-compose.yml` of the pinned release, plus
  NVENC transcoding (`extends: nvenc`) and CUDA machine learning (`-cuda`
  image + `extends: cuda`). The GTX 1060 is passed through to the VM (see
  `proxmox/README.md`).
- `example.env`: the VM's `.env` without secrets. **`IMMICH_VERSION` is
  pinned** (`release` floats, so any `docker compose pull` would upgrade).
- Data: library, thumbs and Immich's nightly DB dumps (`backups/`, 02:00) on
  ZFS `storage/immich` (virtiofs `immich-fs` → `/mnt/zfs/immich`), Postgres on
  the VM disk (`/var/lib/immich/postgres`).

## Upgrading

1. Read the release notes of every version in between
   (<https://github.com/immich-app/immich/releases>), especially breaking
   changes and `.env` changes.
2. Here: take the release's `docker-compose.yml`, `hwaccel.transcoding.yml`
   and `hwaccel.ml.yml`; re-apply the local changes above; bump
   `IMMICH_VERSION` in `example.env`. Merge.
3. Safety net, on the Proxmox host: stop Immich, then
   `qm snapshot 102 pre-immich-<version>` (instant; covers Postgres on the VM
   disk; the photos on ZFS aren't changed by an upgrade).
4. On VM 102 in `/home/jarle/immich-app`: fetch the files from `main`, set
   `IMMICH_VERSION` in `.env`, `docker compose config` (check both GPU
   reservations), `docker compose pull && docker compose up -d`,
   `docker logs -f immich_server` until the migrations are done.
5. Check: `curl -s 192.168.0.52:2283/api/server/version`, web UI,
   Administration → Jobs, a smart search (Grafana → GPU row shows compute
   load), an upload from the phone.
6. Phone/tablet apps and any CLI / immich-go must match the server's major
   version (a v2 CLI against v3 uploads files that never register).
7. A few days later: `qm delsnapshot 102 pre-immich-<version>`.

**Rollback:** `qm rollback 102 pre-immich-<version>` (VM disk incl. Postgres
back to before the upgrade; uploads made after the snapshot are in the library
but not in the DB). Without a snapshot: restore the matching DB dump from
`backups/` (<https://docs.immich.app/administration/backup-and-restore>) or the
weekly vzdump image of VM 102.

## History

- 2026-11-09: v2.7.5 → v3.3.6. The DB already ran VectorChord (`vchord`
  0.4.3, `vector` 0.8.1), so the v3 pgvecto.rs removal needed nothing; `.env`
  had none of the variables v3 dropped. Version pinned from then on.
