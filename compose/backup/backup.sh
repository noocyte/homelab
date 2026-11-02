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

# TeslaMate dumps (written to ZFS at 02:30). Mirror only: retention is
# handled by dump.sh (14 days), so no --backup-dir archive here.
if [ -n "$(ls -A /sources/teslamate 2>/dev/null)" ]; then
  log "syncing teslamate dumps"
  rclone sync /sources/teslamate jottacrypt:teslamate \
    --include '*.dump' \
    --log-level INFO
fi

log "done"
