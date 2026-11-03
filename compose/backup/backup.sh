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
FAILED=""

# Immich: ship originals + DB dump, skip regenerable derivatives
log "syncing immich"
rclone sync /sources/immich jottacrypt:immich \
  --exclude '/thumbs/**' \
  --exclude '/encoded-video/**' \
  --backup-dir "jottacrypt:archive/immich/$DATE" \
  --log-level INFO

# Everything else: each service writes its own backups to the ZFS share,
# one folder each (see compose.yaml). Mirror each folder; the services keep
# their own history (dated files/folders), so no --backup-dir here.
B=/sources/backups
if ! [ -d "$B/teslamate" ]; then
  # Never mirror an empty/unmounted share: rclone sync would delete the
  # off-site copies.
  log "WARNING: $B not mounted, skipping everything but immich"
else
  for d in komodo teslamate trip-planner victoriametrics homeassistant proxmox onedrive crafty; do
    if [ -n "$(ls -A "$B/$d" 2>/dev/null)" ]; then
      log "syncing $d"
      rclone sync "$B/$d" "jottacrypt:$d" \
        --exclude '*.partial' --exclude '*.partial/**' \
        --exclude '*.dat' --exclude '*.tmp/**' \
        --log-level INFO || { log "ERROR: $d failed"; FAILED="$FAILED $d"; }
    else
      log "WARNING: $B/$d is empty or missing, skipping"
    fi
  done
fi

# Personal archive (old NAS: KNX project, code, configs). Unlike the
# service folders there's no history here, so changed/deleted files are
# kept in archive/personal-archive/<date> on Jotta.
if grep -q " /sources/archive nfs" /proc/mounts && [ -n "$(ls -A /sources/archive 2>/dev/null)" ]; then
  log "syncing personal archive"
  rclone sync /sources/archive jottacrypt:personal-archive \
    --backup-dir "jottacrypt:archive/personal-archive/$DATE" \
    --log-level INFO || { log "ERROR: personal archive failed"; FAILED="$FAILED personal-archive"; }
else
  log "WARNING: /sources/archive not mounted or empty, skipping personal archive"
fi

[ -z "$FAILED" ] || { log "failed:$FAILED"; exit 1; }
log "done"
