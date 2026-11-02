#!/bin/sh
# Declares Pi-hole blocklists and allow/deny entries. Idempotent: safe to run
# after every deploy (Komodo post_deploy). Adding a line here + redeploy =
# list added. Removing a line does NOT delete it from Pi-hole.
set -eu

C=pihole

# Wait for Pi-hole to be ready (gravity.db exists)
i=0
until docker exec "$C" test -f /etc/pihole/gravity.db 2>/dev/null; do
  i=$((i+1)); [ "$i" -gt 60 ] && { echo "pihole not ready" >&2; exit 1; }
  sleep 2
done

sql() { docker exec "$C" pihole-FTL sqlite3 /etc/pihole/gravity.db "$1"; }

# --- Blocklists ---------------------------------------------------------
for url in \
  https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts \
  https://v.firebog.net/hosts/Easylist.txt \
  https://v.firebog.net/hosts/RPiList-Phishing.txt \
  https://codeberg.org/hagezi/mirror2/raw/branch/main/dns-blocklists/adblock/pro.txt
do
  sql "INSERT OR IGNORE INTO adlist (address, enabled, comment) VALUES ('$url', 1, 'homelab repo');"
done

# --- Domain lists -------------------------------------------------------
# type: 0 = exact allow, 1 = exact deny, 2 = regex allow, 3 = regex deny
add() { sql "INSERT OR IGNORE INTO domainlist (type, domain, enabled, comment) VALUES ($1, '$2', 1, 'homelab repo');"; }

add 0 'a-fds.playbackquality.tv2.no'
add 0 'firebaselogging.googleapis.com'
add 0 'auth.split.io'
add 0 'click.discord.com'
add 0 's.click.aliexpress.com'
add 0 'www.kqzyfj.com'
add 2 'track.adtraction.com'
add 2 'www.emjcd.com'
add 2 '(\.|^)offers-images\.eu\.placewise\.com$'

# Rebuild gravity so new lists take effect
docker exec "$C" pihole -g >/dev/null
echo "pihole lists applied"
