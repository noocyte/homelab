#!/usr/bin/env bash
# Builds build/docker-host.ign from flatcar/docker-host.bu.
#
# - Creates secrets/komodo.env on first run (random passwords), keeps it after.
# - Runs Butane in a container (podman or docker), so nothing to install.
#
# Usage: scripts/build-ignition.sh
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p secrets build
chmod 700 secrets

if [[ ! -f secrets/komodo.env ]]; then
  echo "Creating secrets/komodo.env with random passwords"
  umask 077
  while IFS= read -r line; do
    while [[ "$line" == *__RANDOM__* ]]; do
      line="${line/__RANDOM__/$(openssl rand -hex 24)}"
    done
    printf '%s\n' "$line"
  done < komodo/compose.env.example > secrets/komodo.env
fi

engine=$(command -v podman || command -v docker || true)
[[ -n "$engine" ]] || { echo "Need podman or docker to run Butane" >&2; exit 1; }

"$engine" run --rm -i --security-opt label=disable \
  -v "$PWD":/work:ro -w /work \
  quay.io/coreos/butane:release \
  --strict --files-dir /work < flatcar/docker-host.bu > build/docker-host.ign

chmod 600 build/docker-host.ign
echo "Wrote build/docker-host.ign (contains secrets, git-ignored)"
grep -E '^KOMODO_INIT_ADMIN_(USERNAME|PASSWORD)=' secrets/komodo.env | sed 's/^/  /'
