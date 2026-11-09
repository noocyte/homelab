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
# After a good run, for backup-status.sh (the tree is too big to measure
# every 15 min):
#   $DEST/.status-<name> = time
#   $DEST/.size-<name>   = "<copy bytes> <copy + .deleted bytes> <OneDrive used bytes>"
# OneDrive's "used" also counts Personal Vault and version history, so it is
# a few % above the copy; a growing gap means the copy is falling behind.
set -eu
DEST=/onedrive
KEEP_DAYS=30
DATE="$(date +%F)"
log() { echo "[onedrive $(date -Iseconds)] $*"; }

measure() {  # measure <name> <remote>  - exact du of the copy (~3.5 min over NFS)
  copy=$(du -sk "$DEST/$1" | cut -f1)
  kept=$(du -skc "$DEST"/.deleted/*/"$1" 2>/dev/null | tail -1 | cut -f1)
  used=$(rclone about "$2" --full | awk '$1 == "Used:" { print $2 }')
  echo "$(( ${copy:-0} * 1024 )) $(( (${copy:-0} + ${kept:-0}) * 1024 )) ${used:-0}" > "$DEST/.size-$1.tmp"
  mv "$DEST/.size-$1.tmp" "$DEST/.size-$1"
}

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
OK=""
for remote in $(rclone listremotes | grep '^onedrive-'); do
  name="${remote#onedrive-}"; name="${name%:}"
  log "syncing $remote → $DEST/$name"
  rclone sync "$remote" "$DEST/$name" \
    --backup-dir "$DEST/.deleted/$DATE/$name" \
    --exclude '/Personal Vault/**' \
    --fast-list --transfers 8 --checkers 16 \
    --log-level INFO --stats 10m --stats-log-level NOTICE \
    && { date +%s > "$DEST/.status-$name"; OK="$OK $name"; } \
    || { log "ERROR: $remote failed"; FAILED="$FAILED $name"; }
done

# Prune the deleted-files area.
if [ -d "$DEST/.deleted" ]; then
  find "$DEST/.deleted" -mindepth 1 -maxdepth 1 -type d -mtime +"$KEEP_DAYS" -exec rm -rf {} +
fi

for name in $OK; do
  log "measuring $name"
  measure "$name" "onedrive-$name:" || log "size check for $name failed"
done

[ -z "$FAILED" ] || { log "failed:$FAILED"; exit 1; }
log "done"
