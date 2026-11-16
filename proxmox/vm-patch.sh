#!/bin/bash
# Patch a VM unattended: snapshot, apt full-upgrade, reboot, health check.
# Runs on the Proxmox host as root; talks to the VM through the QEMU guest
# agent, so it needs no SSH keys or sudo inside the VM. The result (OK or
# FAILED) is mailed to root, which the "phone" notification matcher pushes to
# the phone via Home Assistant. See README.md → "VM 102: monthly patching".
#
#   vm-patch.sh patch   snapshot + upgrade + reboot + checks
#   vm-patch.sh prune   delete this script's snapshots older than KEEP_DAYS,
#                       except snapshots from a failed run
#   vm-patch.sh check   only the health checks (no snapshot, upgrade or reboot)
set -uo pipefail

VMID=102
VM_IP=192.168.0.52
KEEP_DAYS=5
PREFIX=auto-patch-
STATE=/var/lib/vm-patch
LOG=/var/log/vm-patch.log

mkdir -p "$STATE"
exec > >(tee -a "$LOG") 2>&1

log() { echo "$(date '+%F %T') $*"; }

notify() {
  printf '%s\n' "$2" | mail -s "$1" root
}

# Run a shell command in the VM as root. Prints its output, returns its exit code.
guest() {
  local timeout=$1; shift
  qm guest exec "$VMID" --timeout "$timeout" -- bash -c "$*" | python3 -c '
import json, sys
r = json.load(sys.stdin)
sys.stdout.write(r.get("out-data", "") + r.get("err-data", ""))
sys.exit(r.get("exitcode", 1) if r.get("exited") else 124)'
}

wait_for() {
  local what=$1 secs=$2; shift 2
  local end=$((SECONDS + secs))
  until "$@" >/dev/null 2>&1; do
    ((SECONDS >= end)) && { log "timeout waiting for $what"; return 1; }
    sleep 10
  done
  log "$what OK"
}

check_gpu()    { guest 60 nvidia-smi -L; }
check_plex()   { curl -fsS --max-time 10 "http://$VM_IP:32400/identity"; }
check_immich() { curl -fsS --max-time 10 "http://$VM_IP:2283/api/server/ping" | grep -q pong; }
check_gpu_exporter() { curl -fsS --max-time 10 "http://$VM_IP:9835/metrics" | grep -q '^nvidia_smi_gpu_info'; }

patch() {
  local snap="$PREFIX$(date +%Y%m%d)"
  local fail=""
  log "=== patch VM $VMID, snapshot $snap"

  qm agent "$VMID" ping || { notify "VM $VMID patch FAILED" "Guest agent not answering; nothing was changed."; return 1; }

  if ! qm snapshot "$VMID" "$snap" --vmstate 0 --description "Before unattended apt full-upgrade (vm-patch.sh)"; then
    notify "VM $VMID patch FAILED" "Snapshot $snap failed; nothing was changed."
    return 1
  fi

  local out
  out=$(guest 3600 'export DEBIAN_FRONTEND=noninteractive
    apt-get update -q >/var/log/vm-patch-apt.log 2>&1 &&
    apt-get -y -q -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold \
      full-upgrade >>/var/log/vm-patch-apt.log 2>&1
    rc=$?
    grep -E "^[0-9]+ upgraded" /var/log/vm-patch-apt.log | tail -1
    [ -e /var/run/reboot-required ] && echo REBOOT-REQUIRED
    exit $rc')
  local rc=$?
  log "apt: rc=$rc $out"
  local summary
  summary=$(grep -E '^[0-9]+ upgraded' <<<"$out" || echo "no summary")

  if ((rc != 0)); then
    fail="apt full-upgrade failed (rc=$rc), VM not rebooted. Log in the VM: /var/log/vm-patch-apt.log"
  else
    if [[ $summary == "0 upgraded, 0 newly installed"* ]] && ! grep -q REBOOT-REQUIRED <<<"$out"; then
      log "nothing upgraded, no reboot"
    else
      log "rebooting VM $VMID"
      qm reboot "$VMID" --timeout 600 || fail="qm reboot failed"
      [[ -z $fail ]] && { wait_for "guest agent" 600 qm agent "$VMID" ping || fail="VM did not come back (guest agent)"; }
    fi
    if [[ -z $fail ]]; then
      local bad=()
      wait_for "GPU (nvidia-smi)" 300 check_gpu || bad+=("GPU/nvidia-smi")
      wait_for "Plex" 300 check_plex || bad+=("Plex")
      wait_for "Immich" 300 check_immich || bad+=("Immich")
      wait_for "GPU exporter" 300 check_gpu_exporter || bad+=("gpu-exporter")
      ((${#bad[@]})) && fail="after the update these did not answer: ${bad[*]}"
    fi
  fi

  if [[ -n $fail ]]; then
    touch "$STATE/$snap.failed"
    log "FAILED: $fail"
    notify "VM $VMID patch FAILED" "$fail
$summary
Snapshot $snap is kept (not pruned). Roll back on the Proxmox host: qm rollback $VMID $snap
Log: $LOG"
    return 1
  fi
  log "OK: $summary"
  notify "VM $VMID patched OK" "$summary. GPU, Plex, Immich and the GPU exporter answer.
Snapshot $snap is deleted automatically after $KEEP_DAYS days."
}

prune() {
  local cutoff
  cutoff=$(date -d "-$KEEP_DAYS days" +%Y%m%d)
  { qm listsnapshot "$VMID" | grep -oE "$PREFIX[0-9]{8}" || true; } | sort -u | while read -r snap; do
    local day=${snap#"$PREFIX"}
    if [[ -e $STATE/$snap.failed ]]; then
      log "keep $snap (from a failed run)"
    elif [[ $day < $cutoff || $day == "$cutoff" ]]; then
      log "delete snapshot $snap"
      qm delsnapshot "$VMID" "$snap" || notify "VM $VMID snapshot cleanup FAILED" "qm delsnapshot $VMID $snap failed. Log: $LOG"
    fi
  done
}

check() {
  local bad=()
  check_gpu >/dev/null 2>&1 || bad+=("GPU/nvidia-smi")
  check_plex >/dev/null 2>&1 || bad+=("Plex")
  check_immich >/dev/null 2>&1 || bad+=("Immich")
  check_gpu_exporter >/dev/null 2>&1 || bad+=("gpu-exporter")
  ((${#bad[@]})) && { log "check FAILED: ${bad[*]}"; return 1; }
  log "check OK: GPU, Plex, Immich, gpu-exporter"
}

case ${1:-} in
  patch) patch ;;
  prune) prune ;;
  check) check ;;
  *) echo "usage: $0 patch|prune|check" >&2; exit 2 ;;
esac
