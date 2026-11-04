#!/bin/sh
# Nightly one-way copy of personal OneDrive accounts to the ZFS share.
# Runs in the rclone-onedrive container (Ofelia, 02:00). Every remote in
# /config/rclone.conf named onedrive-<name> is copied to /onedrive/<name>.
#
# Read-only towards OneDrive: nothing there is ever changed. Files that are
# deleted or overwritten in OneDrive are not lost here at once: they move
# to /onedrive/.deleted/<date>/<name>/ and are removed after KEEP_DAYS.
# The backup job mirrors /mnt/backups/onedrive to Jotta at 03:00.
# Not copied: Personal Vault (locked; rclone can't read it).
# After a good run: $DEST/.status-<name> = time (for backup-status.sh).
set -eu
DEST=/onedrive
KEEP_DAYS=30
DATE="$(date +%F)"
log() { echo "[onedrive $(date -Iseconds)] $*"; }

# Refuse to write to the VM's own disk if the NFS share isn't mounted.
grep -q " $DEST nfs" /proc/mounts || { log "$DEST is not the NFS share, aborting"; exit 1; }

# One run at a time: the first copy of an account can take longer than a day.
LOCK=/tmp/onedrive.lock
if ! mkdir "$LOCK" 2>/dev/null; then
  if kill -0 "$(cat "$LOCK/pid" 2>/dev/null)" 2>/dev/null; then
    log "another run is in progress (pid $(cat "$LOCK/pid")), skipping"
    exit 0
  fi
  rm -rf "$LOCK"; mkdir "$LOCK"
fi
echo $$ > "$LOCK/pid"
trap 'rm -rf "$LOCK"' EXIT

FAILED=""
for remote in $(rclone listremotes | grep '^onedrive-'); do
  name="${remote#onedrive-}"; name="${name%:}"
  log "syncing $remote → $DEST/$name"
  rclone sync "$remote" "$DEST/$name" \
    --backup-dir "$DEST/.deleted/$DATE/$name" \
    --exclude '/Personal Vault/**' \
    --fast-list --transfers 8 --checkers 16 \
    --log-level INFO --stats 10m --stats-log-level NOTICE \
    && date +%s > "$DEST/.status-$name" \
    || { log "ERROR: $remote failed"; FAILED="$FAILED $name"; }
done

# Prune the deleted-files area.
if [ -d "$DEST/.deleted" ]; then
  find "$DEST/.deleted" -mindepth 1 -maxdepth 1 -type d -mtime +"$KEEP_DAYS" -exec rm -rf {} +
fi

[ -z "$FAILED" ] || { log "failed:$FAILED"; exit 1; }
log "done"
