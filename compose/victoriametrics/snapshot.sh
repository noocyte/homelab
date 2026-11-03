#!/bin/sh
# Consistent point-in-time snapshot for the offsite backup. Snapshots are
# hardlinks (no extra disk until data is merged away), so only the newest is
# kept. Runs inside the victoriametrics container (Alpine: sh + wget).
set -eu
URL=http://127.0.0.1:8428

wget -qO- "$URL/snapshot/delete_all" >/dev/null
out="$(wget -qO- "$URL/snapshot/create")"
case "$out" in
  *'"status":"ok"'*) echo "snapshot ok: $out" ;;
  *) echo "snapshot FAILED: $out" >&2; exit 1 ;;
esac
