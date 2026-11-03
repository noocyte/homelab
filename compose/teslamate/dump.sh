#!/bin/sh
# Nightly dump of the TeslaMate databases to the ZFS share on Proxmox.
# Runs INSIDE the database container (Ofelia job-exec, see compose.yaml).
# /backups = /mnt/backups/teslamate on the host (NFS → Proxmox ZFS).
set -eu
DIR=/backups
KEEP_DAYS=14

# Refuse to write to the VM's own disk if the NFS share isn't mounted.
fstype=$(stat -f -c %T "$DIR")
case "$fstype" in
  nfs*) ;;
  *) echo "[dump] $DIR is '$fstype', not NFS: ZFS share not mounted, aborting" >&2; exit 1 ;;
esac

ts=$(date +%Y-%m-%d_%H%M)
for db in teslamate mg_ismart; do
  pg_dump -U "$POSTGRES_USER" -Fc -f "$DIR/$db-$ts.dump.partial" "$db"
  mv "$DIR/$db-$ts.dump.partial" "$DIR/$db-$ts.dump"
  echo "[dump] $db-$ts.dump $(du -h "$DIR/$db-$ts.dump" | cut -f1)"
done

find "$DIR" -name '*.dump' -mtime +"$KEEP_DAYS" -delete
find "$DIR" -name '*.partial' -mmin +720 -delete
echo "[dump] done"
