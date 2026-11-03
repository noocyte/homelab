# Nightly backup of Crafty: its database + config and every Minecraft
# server (worlds, mods, settings) → /nightly/crafty-<date>.tar.gz, 14 kept.
# Runs inside the Crafty container (Ofelia job-exec, 02:40).
# /nightly = /mnt/backups/crafty/nightly on the host (NFS → Proxmox ZFS);
# the backup stack mirrors /mnt/backups/crafty to Jotta at 03:00.
#
# The database is copied with SQLite's online backup API (consistent while
# Crafty runs). Worlds of a server that is running at 02:40 are copied as
# they are on disk; Minecraft saves every few minutes, so at worst the last
# minutes are missing.
#
# Restore: stop the stack, then
#   tar -xzf crafty-<date>.tar.gz -C /srv/crafty
#   mv /srv/crafty/config/db/crafty.sqlite.backup /srv/crafty/config/db/crafty.sqlite
# and start it again.
import datetime
import os
import sqlite3
import sys
import tarfile

DEST = "/nightly"
KEEP_DAYS = 14
CONFIG = "/crafty/app/config"
SERVERS = "/crafty/servers"
DB = os.path.join(CONFIG, "db", "crafty.sqlite")

# Refuse to write to the VM's own disk if the NFS share isn't mounted.
fstype = next((l.split()[2] for l in open("/proc/mounts") if l.split()[1] == DEST), None)
if not (fstype or "").startswith("nfs"):
    sys.exit(f"{DEST} is {fstype!r}, not NFS: ZFS share not mounted, aborting")

day = datetime.date.today().isoformat()
out = os.path.join(DEST, f"crafty-{day}.tar.gz")
tmp = out + ".partial"
dbcopy = "/tmp/crafty.sqlite.backup"

src = sqlite3.connect(DB)
dst = sqlite3.connect(dbcopy)
src.backup(dst)
src.close()
ok = dst.execute("PRAGMA integrity_check").fetchone()[0]
dst.close()
if ok != "ok":
    sys.exit(f"database integrity check failed: {ok}")


def skip_live_db(ti):
    return None if ti.name.startswith("config/db/crafty.sqlite") else ti


with tarfile.open(tmp, "w:gz", compresslevel=6) as tar:
    tar.add(CONFIG, arcname="config", filter=skip_live_db)
    tar.add(dbcopy, arcname="config/db/crafty.sqlite.backup")
    tar.add(SERVERS, arcname="servers")
os.remove(dbcopy)
os.replace(tmp, out)  # atomic: the offsite copy never sees a half-written file

cutoff = (datetime.date.today() - datetime.timedelta(days=KEEP_DAYS)).isoformat()
for f in os.listdir(DEST):
    if f.startswith("crafty-") and f.endswith(".tar.gz") and f[7:17] < cutoff:
        os.remove(os.path.join(DEST, f))

print(f"backup ok: {out} ({os.path.getsize(out) // 1_000_000} MB)")
