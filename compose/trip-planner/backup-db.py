# Consistent copy of the live TRIP database (WAL mode - a plain file copy
# can be torn). Run nightly by Ofelia inside the app container, which has
# Python but no sqlite3 CLI. The backup stack ships storage/ offsite at 03:00.
import os
import sqlite3
import sys

SRC = "/app/storage/trip.sqlite"
DST = "/app/storage/backups/trip-nightly.sqlite"
TMP = DST + ".partial"

os.makedirs(os.path.dirname(DST), exist_ok=True)
if os.path.exists(TMP):
    os.remove(TMP)

src = sqlite3.connect(SRC)
dst = sqlite3.connect(TMP)
src.backup(dst)  # online backup API: consistent snapshot while the app runs
src.close()

result = dst.execute("PRAGMA integrity_check").fetchone()[0]
tables = dst.execute("SELECT count(*) FROM sqlite_master WHERE type = 'table'").fetchone()[0]
dst.close()
if result != "ok":
    os.remove(TMP)
    sys.exit(f"integrity check failed: {result}")

os.replace(TMP, DST)  # atomic: offsite never sees a half-written file
print(f"backup ok: {DST} ({os.path.getsize(DST)} bytes, {tables} tables)")
