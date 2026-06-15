#!/bin/sh
set -eu
DATE="$(date +%F)"
log() { echo "[backup $(date -Iseconds)] $*"; }

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

log "done"