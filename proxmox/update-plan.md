# Proxmox update plan (assessed 2026-11-03, not done yet)

State on 2026-11-03: PVE 9.2.3, kernel 7.0.6-2-pve, last `apt` run 2026-06-15.
`apt-get -s dist-upgrade`: **195 upgrades + 5 new**, of which 28 Debian
security updates; pve-manager 9.2.3 → 9.2.25, pve-qemu-kvm 11.0 → 11.1.3,
qemu-server 9.1 → 9.2, ZFS userland 2.4.2 → 2.4.4, new kernels 7.0.14-26
and 6.17.13-21, new OVMF firmware. Repos: Debian trixie + pve-no-subscription.

## The real risk: NVIDIA on the host

- The host has NVIDIA's own driver **595.71.05 via DKMS** (built for all
  installed kernels) and NVIDIA's suspend/resume/hibernate services enabled.
  The host doesn't need it: the GTX 1060 (01:00.0 `10de:1c02`, audio
  01:00.1 `10de:10f1`) is passed through to VM 102 and is bound to
  `vfio-pci`.
- Nothing reserves the GPU for vfio explicitly (no `vfio-pci ids=`, `nvidia`
  not blacklisted; only nouveau/nvidiafb are). Today `nvidia` happens not to
  load.
- A new kernel means: DKMS must build NVIDIA's driver for it (a failed build
  leaves apt half-configured), and after the reboot `nvidia` could grab the
  GPU before `vfio-pci` → VM 102 loses its GPU (Plex/Immich acceleration).
  Probably what went wrong last time.

Other risks are small: every guest is down ~5 min per reboot **including
Pi-hole, so the house has no DNS** meanwhile; ZFS 2.4.4 is a patch release
(no pool upgrade); the old kernel stays installed as a fallback.

## Plan (two short outages - evening/night)

Before: check that last night's backups reached Jotta, and that the weekly
vzdump images of VM 102 / LXC 100 are recent.

1. **Reserve the GPU for passthrough** (Proxmox shell):
   ```sh
   cat > /etc/modprobe.d/vfio.conf <<'EOF'
   options vfio-pci ids=10de:1c02,10de:10f1
   softdep nvidia pre: vfio-pci
   softdep nouveau pre: vfio-pci
   EOF
   cat > /etc/modprobe.d/blacklist-nvidia-host.conf <<'EOF'
   blacklist nvidia
   blacklist nvidia_drm
   blacklist nvidia_modeset
   blacklist nouveau
   EOF
   update-initramfs -u -k all
   ```
2. **Remove the host's unused NVIDIA driver** so DKMS has nothing to build:
   `nvidia-uninstall` (it came from NVIDIA's .run installer), then check
   `dkms status` is empty and disable the leftover `nvidia-*` services.
3. **Reboot (outage 1)** with only that change. Check:
   `lspci -nnk -s 01:00` → `vfio-pci`; VM 102 starts; in VM 102 `nvidia-smi`
   works; Plex (:32400) and Immich (:2283) answer.
4. **Update:** `apt update && apt full-upgrade`. Watch for DKMS/initramfs
   errors at the end.
5. **Reboot (outage 2)** into 7.0.14. Same checks as step 3, plus
   `pveversion`, `zpool status`, all guests running, Pi-hole answering.

6. **Temperature and disk-health metrics** (only after the update - on the
   un-updated host, `apt install` pulled in 14 core upgrades such as
   util-linux/mount/login, 2026-11-03):
   ```sh
   apt install prometheus-node-exporter prometheus-node-exporter-collectors
   ```
   node_exporter on `:9100`: CPU temperatures (coretemp/hwmon), ZFS (ARC,
   pool state), disk I/O, filesystems. The collectors package adds a SMART
   textfile collector (`smartmon`, a systemd timer using the host's
   smartctl) → temperature, reallocated/pending sectors, power-on hours and
   SMART status for the four ZFS disks and the SSD. Check
   `curl -s localhost:9100/metrics | grep -E "node_hwmon_temp|smartmon_"`;
   if the HDD temperatures are missing from hwmon, `modprobe drivetemp` (and
   add it to `/etc/modules`).
   Then in the repo: a scrape job `proxmox-node` (`192.168.0.107:9100`) in
   `compose/victoriametrics/scrape.yml`, and dashboards "Node Exporter Full"
   (grafana.com 1860) and a SMART/smartmon dashboard in the Grafana folder
   **Proxmox**, provisioned like the others.

   **GPU temperature** isn't visible on the host (passed through to VM 102).
   Independent of this plan: an `nvidia_gpu_exporter` container in VM 102
   (reads `nvidia-smi`; temperature, load, memory, fan, power), scraped the
   same way, plus an NVIDIA dashboard.

**Rollback:** GPU trouble on the new kernel → `proxmox-boot-tool kernel pin
7.0.6-2-pve` and reboot; unpin later with `proxmox-boot-tool kernel unpin`.
Step 1 undone by deleting the two files and `update-initramfs -u -k all`.

Afterwards: update `proxmox/README.md` (version, the vfio binding) and this
file's status.
