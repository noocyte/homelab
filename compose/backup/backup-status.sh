#!/bin/sh
# Backup status, every 15 min (Ofelia, rclone-backup container).
#
# Looks at what the backup jobs left on the ZFS share and when each folder
# last reached Jotta, then
#   - pushes the numbers to VictoriaMetrics (Grafana: Backups dashboard),
#   - tells Home Assistant (webhook HA_WEBHOOK_URL): a heartbeat with a
#     one-line summary every run, plus one message when a backup turns late
#     and one when it is back. HA turns those into phone notifications.
#
# A backup is late when its newest file is older than its interval + 4 h
# (daily → 28 h, weekly → 7 d 4 h); off-site when a folder hasn't reached
# Jotta for 36 h. Read-only towards the backups; state lives in /config/status.
set -u
B=/sources/backups
S=/config/status          # offsite-<folder>: written by backup.sh; alert-<key>: who is late
VM="${VM_URL:-http://192.168.0.240:8428}"
HOOK="${HA_WEBHOOK_URL:-}"
NOW=$(date +%s)
DAY=86400
WEEK=604800
mkdir -p "$S"
OUT=""
BAD=""
N_OK=0
N_ALL=0

metric() { OUT="$OUT
$1"; }

ha() {   # ha <json>  - quiet; returns non-zero if HA didn't take it
  [ -n "$HOOK" ] || return 1
  wget -q -O /dev/null -T 15 --header 'Content-Type: application/json' --post-data "$1" "$HOOK"
}

age() {  # seconds → "3 d 4 h" / "5 h" / "12 min"
  a=$1
  if [ "$a" -ge "$DAY" ]; then echo "$((a / DAY)) d $((a % DAY / 3600)) h"
  elif [ "$a" -ge 3600 ]; then echo "$((a / 3600)) h"
  else echo "$((a / 60)) min"; fi
}

# judge <key> <label> <timestamp> <limit-seconds> <metric-name> <label-name>
judge() {
  key=$1; label=$2; ts=$3; limit=$4
  N_ALL=$((N_ALL + 1))
  if [ "$ts" -gt 0 ] && [ $((NOW - ts)) -le "$limit" ]; then
    ok=1; N_OK=$((N_OK + 1))
    if [ -e "$S/alert-$key" ] && ha "{\"type\":\"recovered\",\"title\":\"Backup OK again\",\"message\":\"$label is up to date again.\"}"; then
      rm -f "$S/alert-$key"
    fi
  else
    ok=0; BAD="$BAD $key"
    if [ "$ts" -gt 0 ]; then when="last one $(age $((NOW - ts))) ago"; else when="none found"; fi
    if [ ! -e "$S/alert-$key" ] && ha "{\"type\":\"late\",\"title\":\"Backup late\",\"message\":\"$label: $when.\"}"; then
      touch "$S/alert-$key"
    fi
  fi
  metric "$5{$6=\"${key#offsite-}\"} $ok"
}

# Newest file matching <pattern> directly in <dir>: "mtime size"
newest_file() {
  find "$1" -maxdepth 1 -type f -name "$2" ! -name '*.partial' -exec stat -c '%Y %s' {} + 2>/dev/null | sort -n | tail -1
}
# Newest folder matching <pattern> directly in <dir>: "mtime kbytes"
newest_dir() {
  d=$(find "$1" -mindepth 1 -maxdepth 1 -type d -name "$2" -exec stat -c '%Y %n' {} + 2>/dev/null | sort -n | tail -1)
  [ -n "$d" ] || return 0
  echo "${d%% *} $(( $(du -sk "${d#* }" | cut -f1) * 1024 ))"
}

# Total bytes of the files matching <pattern> directly in <dir>
sum_files() {
  find "$1" -maxdepth 1 -type f -name "$2" -exec stat -c '%s' {} + 2>/dev/null | awk '{ s += $1 } END { print s + 0 }'
}

# local <job> <label> <interval> <folder to du, "" = use total> <"mtime bytes"> [total bytes]
local_job() {
  job=$1; label=$2; interval=$3; dir=$4; total=${6:-0}; set -- $5
  ts=${1:-0}; bytes=${2:-0}
  if [ -n "$dir" ]; then kb=$(du -sk "$dir" 2>/dev/null | cut -f1); total=$(( ${kb:-0} * 1024 )); fi
  metric "backup_last_timestamp_seconds{job=\"$job\"} $ts"
  metric "backup_last_bytes{job=\"$job\"} $bytes"
  metric "backup_total_bytes{job=\"$job\"} $total"
  metric "backup_expected_interval_seconds{job=\"$job\"} $interval"
  judge "$job" "$label" "$ts" $((interval + 4 * 3600)) backup_ok job
}

# Never judge an unmounted share (everything would look missing).
if ! grep -q " $B nfs" /proc/mounts || ! [ -d "$B/teslamate" ]; then
  ha '{"type":"late","title":"Backup status","message":"The ZFS backup share is not mounted on the docker VM."}'
  exit 1
fi

local_job komodo          "Komodo"              $DAY  "$B/komodo"          "$(newest_dir  "$B/komodo" '20*')"
local_job teslamate       "TeslaMate DB"        $DAY  "$B/teslamate"       "$(newest_file "$B/teslamate" 'teslamate-*.dump')"
local_job trip-planner    "Trip planner"        $DAY  "$B/trip-planner"    "$(newest_dir  "$B/trip-planner" '20*')"
local_job crafty          "Crafty / Minecraft"  $DAY  "$B/crafty"          "$(newest_file "$B/crafty/nightly" 'crafty-*.tar.gz')"
local_job homeassistant   "Home Assistant"      $DAY  "$B/homeassistant"   "$(newest_file "$B/homeassistant" '*.tar')"
# The cabin's HA, over Tailscale → Samba share "Cabin" on the NAS (see README).
local_job homeassistant-cabin "Home Assistant (cabin)" $DAY "$B/homeassistant-cabin" "$(newest_file "$B/homeassistant-cabin" '*.tar')"
local_job proxmox-host    "Proxmox host config" $DAY  "$B/proxmox/host"    "$(newest_file "$B/proxmox/host" 'pve-host-*.tar.gz')"
# Both guests share proxmox/dump: total = only this guest's files.
local_job vzdump-102      "VM 102 image (weekly)"  $WEEK "" "$(newest_file "$B/proxmox/dump" 'vzdump-qemu-102-*.zst')" "$(sum_files "$B/proxmox/dump" 'vzdump-qemu-102-*')"
local_job vzdump-100      "LXC 100 image (weekly)" $WEEK "" "$(newest_file "$B/proxmox/dump" 'vzdump-lxc-100-*.zst')" "$(sum_files "$B/proxmox/dump" 'vzdump-lxc-100-*')"
# vmbackup rewrites this marker when a backup completes.
vm=$(stat -c '%Y' "$B/victoriametrics/latest/backup_complete.ignore" 2>/dev/null || echo 0)
local_job victoriametrics "VictoriaMetrics"     $DAY  "$B/victoriametrics" "$vm $(( $(du -sk "$B/victoriametrics/latest" | cut -f1) * 1024 ))"
# OneDrive: onedrive.sh writes .status-<name> (epoch) and .size-<name> after a
# good run; the tree is too big to measure here. Newest size = the copy,
# total = copy + .deleted/, backup_source_bytes = what OneDrive says it holds.
for f in "$B"/onedrive/.status-*; do
  [ -e "$f" ] || continue
  name=${f##*/.status-}
  set -- $(cat "$B/onedrive/.size-$name" 2>/dev/null)
  copy=${1:-0}; total=${2:-0}; source=${3:-0}
  local_job "onedrive-$name" "OneDrive ($name)" $DAY "" "$(cat "$f") $copy" "$total"
  metric "backup_source_bytes{job=\"onedrive-$name\"} $source"
done
# The cabin's HA also uploads each backup (~05:00) to jarle's OneDrive; they
# reach us with the 02:00 copy, so allow 2 days. Second copy, checked too.
CABIN="$B/onedrive/jarle/Apps/Home Assistant/backups_3bf5b0b4"
local_job ha-cabin-onedrive "Home Assistant (cabin, via OneDrive)" $((2 * DAY)) "$CABIN" "$(newest_file "$CABIN" 'Automatic_backup_*.tar')"

# Off-site: backup.sh writes /config/status/offsite-<folder> after each good sync.
for f in "$S"/offsite-*; do
  [ -e "$f" ] || continue
  folder=${f##*/offsite-}
  ts=$(cat "$f")
  metric "backup_offsite_last_success_timestamp_seconds{folder=\"$folder\"} $ts"
  judge "offsite-$folder" "Jotta copy of $folder" "$ts" $((DAY + 12 * 3600)) backup_offsite_ok folder
done

metric "backup_status_last_run_timestamp_seconds $NOW"
wget -q -O /dev/null -T 30 --post-data "$(printf '%s\n' "$OUT" | sed '/^$/d')" "$VM/api/v1/import/prometheus" \
  || echo "push to VictoriaMetrics failed" >&2

if [ -z "$BAD" ]; then summary="All $N_ALL OK"; else summary="$((N_ALL - N_OK)) of $N_ALL late:$BAD"; fi
ha "{\"type\":\"heartbeat\",\"summary\":\"$summary\"}" || echo "Home Assistant webhook not reachable/configured" >&2
echo "$summary"
