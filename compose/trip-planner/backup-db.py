# Nightly backup of TRIP to the ZFS share: /backups/<date>/ holds a
# consistent copy of the database plus attachments, assets and config.env
# (22 MB in total). 14 days are kept; the backup stack mirrors the folder
# to Jotta at 03:00.
#
# Run by Ofelia inside the app container (Python, no sqlite3 CLI).
# /backups = /mnt/backups/trip-planner on the host (NFS → Proxmox ZFS).
#
# Restore: stop the app, copy one dated folder's contents into
# /srv/trip-planner/storage/ and rename trip.sqlite.backup to trip.sqlite
# (delete any trip.sqlite-wal / -shm first), start the app.
import datetime
import os
import shutil
import sqlite3
import sys

STORAGE = "/app/storage"
DEST = "/backups"
KEEP_DAYS = 14

# Refuse to write to the VM's own disk if the NFS share isn't mounted.
fstype = next((l.split()[2] for l in open("/proc/mounts") if l.split()[1] == DEST), None)
if not (fstype or "").startswith("nfs"):
    sys.exit(f"{DEST} is {fstype!r}, not NFS: ZFS share not mounted, aborting")

day = datetime.date.today().isoformat()
out = os.path.join(DEST, day)
tmp = out + ".partial"
shutil.rmtree(tmp, ignore_errors=True)
os.makedirs(tmp)

# Database: online backup API gives a consistent copy while the app runs
# (WAL mode - a plain file copy can be torn).
db = os.path.join(tmp, "trip.sqlite.backup")
src = sqlite3.connect(os.path.join(STORAGE, "trip.sqlite"))
dst = sqlite3.connect(db)
src.backup(dst)
src.close()
result = dst.execute("PRAGMA integrity_check").fetchone()[0]
tables = dst.execute("SELECT count(*) FROM sqlite_master WHERE type = 'table'").fetchone()[0]
dst.close()
if result != "ok":
    shutil.rmtree(tmp)
    sys.exit(f"integrity check failed: {result}")

# Files next to the database.
for name in ("attachments", "assets"):
    if os.path.isdir(os.path.join(STORAGE, name)):
        shutil.copytree(os.path.join(STORAGE, name), os.path.join(tmp, name))
if os.path.exists(os.path.join(STORAGE, "config.env")):
    shutil.copy2(os.path.join(STORAGE, "config.env"), tmp)

# Swap in atomically, so the offsite copy never sees a half-written folder.
shutil.rmtree(out, ignore_errors=True)
os.rename(tmp, out)

# Keep KEEP_DAYS days.
cutoff = (datetime.date.today() - datetime.timedelta(days=KEEP_DAYS)).isoformat()
for d in os.listdir(DEST):
    if len(d) == 10 and d[4] == "-" and d < cutoff:
        shutil.rmtree(os.path.join(DEST, d))

print(f"backup ok: {out} ({tables} tables, db {os.path.getsize(os.path.join(out, 'trip.sqlite.backup'))} bytes)")
