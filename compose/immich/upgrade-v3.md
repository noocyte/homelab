# Immich 2.7.5 → 3.x upgrade (assessed 2026-11-03, not done yet)

Immich runs on VM 102 (`plex-enc`), deployed by hand from
`/home/jarle/immich-app` (copy of this folder). Installed: **v2.7.5**
(April 2026). Latest stable at assessment: **v3.3.5** (2026-10-21).

**Risk: low.** Release notes: <https://github.com/immich-app/immich/releases>,
migration guide: <https://immich.app/blog/v3-migration>.

## Already fine

- **Vector database:** v3.0 drops pgvecto.rs. The database already runs
  **VectorChord** (`vchord 0.4.3`, `vector 0.8.1`; no `vectors` extension) -
  the step that breaks most v2 installs isn't needed.
- **CPU:** v3 ML needs x86-64-v2+. The host's i7-4770 supports v3.
- **GPU:** no CUDA/NVIDIA driver changes in the 3.x notes (CUDA ML image,
  NVENC transcoding).
- **Path:** 2.7.5 is the last v2 release; straight to 3.3.x is fine.
- Not used here: OAuth (stricter defaults in v3), Prometheus metrics (names
  changed `_` → `.`), iOS 14.

## To do

1. **Before:** wait until big imports have finished processing (Administration
   → Jobs all idle). Fresh image of the VM, on the Proxmox host:
   `vzdump 102 --storage backups-proxmox --mode snapshot --compress zstd`
   (~3 min, ~12 GB). **The v3 database migration is one-way** - rollback =
   restore that image (`qmrestore`), or Immich's nightly DB dump in
   `/storage/immich/backups`.
2. **Compose file:** replace `compose.yaml` here (and
   `/home/jarle/immich-app/docker-compose.yml` on VM 102) with the
   `docker-compose.yml` from the target release, re-applying the local
   changes: `extends: … service: nvenc` on immich-server, `-cuda` image
   suffix and the `deploy.resources` GPU reservation on
   immich-machine-learning. Check whether the database image tag changed.
   Same for `hwaccel.transcoding.yml`.
3. **`.env`** (`/home/jarle/immich-app/.env`): remove if present -
   `MACHINE_LEARNING_PRELOAD__CLIP` (→ `…__CLIP__TEXTUAL` / `…__CLIP__VISUAL`),
   `MACHINE_LEARNING_PRELOAD__FACIAL_RECOGNITION` (→ `…__DETECTION` /
   `…__RECOGNITION`), `IMMICH_MACHINE_LEARNING_PING_TIMEOUT` (→ Admin UI,
   `machineLearning.availabilityChecks.timeout`). Set `IMMICH_VERSION` to
   the target (e.g. `v3.3.5`) if it's pinned.
4. **Upgrade** (VM 102, in `/home/jarle/immich-app`):
   `docker compose pull && docker compose up -d`, then watch
   `docker logs -f immich_server` until the migrations finish. Immich is
   down meanwhile (~15 min); Plex is unaffected.
5. **After:** web UI works, Administration → Jobs runs, a photo uploads from
   the phone. **Update the Immich app on every phone/tablet to 3.x** (the
   legacy timeline is gone; old apps may misbehave).
6. **Tools:** use `ghcr.io/immich-app/immich-cli` **3.x** from now on (the CLI
   version must match the server; 2.7.5 against a v3 server - or 3.x against
   v2 - uploads files that never register).
