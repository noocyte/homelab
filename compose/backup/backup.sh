#!/bin/sh
set -eu
DATE="$(date +%F)"
log() { echo "[backup $(date -Iseconds)] $*"; }

# Only one run at a time (nightly job vs. a manual run). The lock is a
# directory holding the PID; a stale lock (dead PID) is taken over.
LOCK=/tmp/backup.lock
if ! mkdir "$LOCK" 2>/dev/null; then
  if kill -0 "$(cat "$LOCK/pid" 2>/dev/null)" 2>/dev/null; then
    log "another run is in progress (pid $(cat "$LOCK/pid")), skipping"
    exit 0
  fi
  log "removing stale lock"
  rm -rf "$LOCK"
  mkdir "$LOCK"
fi
echo $$ > "$LOCK/pid"
trap 'rm -rf "$LOCK"' EXIT

log "starting"

# Immich: ship originals + DB dump, skip regenerable derivatives
log "syncing immich"
rclone sync /sources/immich jottacrypt:immich \
  --exclude '/thumbs/**' \
  --exclude '/encoded-video/**' \
  --backup-dir "jottacrypt:archive/immich/$DATE" \
  --log-level INFO

# Local DB dumps (future) — no-op while empty
if [ -d /sources/dumps ] && [ -n "$(ls -A /sources/dumps 2>/dev/null)" ]; then
  log "syncing dumps"
  rclone sync /sources/dumps jottacrypt:dumps \
    --backup-dir "jottacrypt:archive/dumps/$DATE" \
    --log-level INFO
fi

BIG=/sources/bigbackup   # ZFS backups share on Proxmox (NFS)
if ! [ -d "$BIG/teslamate" ]; then
  # Never mirror an empty/unmounted share: rclone sync would delete the
  # off-site copies.
  log "WARNING: $BIG not mounted, skipping teslamate, homeassistant, proxmox"
else
  # TeslaMate dumps (written at 02:30). Mirror only: retention is handled
  # by dump.sh (14 days), so no --backup-dir archive here.
  if [ -n "$(ls -A "$BIG/teslamate" 2>/dev/null)" ]; then
    log "syncing teslamate dumps"
    rclone sync "$BIG/teslamate" jottacrypt:teslamate \
      --include '*.dump' \
      --log-level INFO
  fi

  # Home Assistant backups (encrypted by HA; key in the password manager).
  # HA keeps the newest ~10 itself, so mirror.
  if ls "$BIG"/automatic_backup_*.tar >/dev/null 2>&1; then
    log "syncing home assistant backups"
    rclone sync "$BIG" jottacrypt:homeassistant \
      --include '/automatic_backup_*.tar' \
      --log-level INFO
  else
    log "WARNING: no home assistant backups found, skipping"
  fi

  # Proxmox: weekly vzdump images (Sun 01:00, Proxmox keeps 2) and the
  # nightly host config tarballs (14 kept). Mirror; skip files vzdump is
  # still writing (*.dat, *.tmp/).
  if [ -d "$BIG/proxmox" ]; then
    log "syncing proxmox"
    rclone sync "$BIG/proxmox" jottacrypt:proxmox \
      --exclude '*.dat' \
      --exclude '*.tmp/**' \
      --exclude '*.part' \
      --log-level INFO
  fi
fi

# Trip planner: whole storage folder (images, config, nightly DB copy made
# at 02:45 by backup-db.py). The live database files are skipped - a copy
# of a WAL-mode database while it's in use can be broken.
if [ -f /sources/trip-planner/backups/trip-nightly.sqlite ]; then
  log "syncing trip-planner"
  rclone sync /sources/trip-planner jottacrypt:trip-planner \
    --exclude '/trip.sqlite' \
    --exclude '/trip.sqlite-wal' \
    --exclude '/trip.sqlite-shm' \
    --exclude '*.partial' \
    --backup-dir "jottacrypt:archive/trip-planner/$DATE" \
    --log-level INFO
else
  log "WARNING: no trip-planner nightly DB copy found, skipping trip-planner"
fi

# VictoriaMetrics: newest snapshot (made at 02:50 by snapshot.sh). Its
# data/ entries are relative symlinks into the storage folder, hence
# --copy-links. Mirror only: the snapshot is the complete database.
SNAP="$(ls -1 /sources/victoriametrics/snapshots 2>/dev/null | sort | tail -n 1)"
if [ -n "$SNAP" ]; then
  log "syncing victoriametrics snapshot $SNAP"
  rclone sync "/sources/victoriametrics/snapshots/$SNAP" jottacrypt:victoriametrics \
    --copy-links \
    --log-level INFO
else
  log "WARNING: no victoriametrics snapshot found, skipping victoriametrics"
fi

log "done"
