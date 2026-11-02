#!/bin/sh
# One-time preparation of the Norway road network for OSRM (used by
# saic2postgresql for map matching). Run on the docker host:
#
#   sudo sh osrm-setup.sh
#
# Writes ~1.5 GB to /srv/teslamate/osrm-data. Takes 5-15 minutes.
# Re-run to refresh the map. Uses the same OSRM image as compose.yaml.
set -eu

OSRM_DIR=/srv/teslamate/osrm-data
PBF_URL=https://download.geofabrik.de/europe/norway-latest.osm.pbf
OSRM_IMAGE=osrm/osrm-backend@sha256:af5d4a83fb90086a43b1ae2ca22872e6768766ad5fcbb07a29ff90ec644ee409

mkdir -p "$OSRM_DIR"
cd "$OSRM_DIR"

[ -f norway-latest.osm.pbf ] || curl -fL -o norway-latest.osm.pbf "$PBF_URL"

docker run --rm -v "$OSRM_DIR:/data" "$OSRM_IMAGE" osrm-extract -p /opt/car.lua /data/norway-latest.osm.pbf
docker run --rm -v "$OSRM_DIR:/data" "$OSRM_IMAGE" osrm-partition /data/norway-latest.osrm
docker run --rm -v "$OSRM_DIR:/data" "$OSRM_IMAGE" osrm-customize /data/norway-latest.osrm

echo "OSRM data ready in $OSRM_DIR - redeploy the teslamate stack."
