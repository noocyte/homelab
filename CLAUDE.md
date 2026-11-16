# CLAUDE.md

Working notes for Claude in this repo. The README is the reference for how
things are built; this file is about how to work here. Don't repeat README
content in this file, point to it.

## How the user wants to work

- **One topic per message.** One finding or proposal and one question, then
  wait. Hold the rest back (at most one line saying there is more).
- **Say what you're about to do and how long it takes** before anything slow
  or visible: deploy waits, test runs, temporary objects in HA, reboots.
  Then say when it's done and cleaned up.
- **Name the machine** for every command you ask the user to run.
- **"What about X?" is a question, not a task.** Answer with an assessment
  and an offer; don't open a PR or touch hosts until asked.
- Don't suggest stopping; offer the next step.

## Machines and access

| Machine | Address | Login | Notes |
|---|---|---|---|
| Proxmox host `pve` | 192.168.0.107 | `root` | Set up by hand, see `proxmox/README.md` |
| docker-host (VM 200, Flatcar) | 192.168.0.240 | `core` | Komodo; everything in `compose/` except the VM 102 stacks |
| plex-enc (VM 102, Ubuntu 24.04) | 192.168.0.52 | `jarle` (no passwordless sudo) | Plex, Immich, gpu-exporter; root via `qm guest exec 102` on the host |
| Home Assistant (HAOS) | 192.168.0.63 | `root` via the Advanced SSH add-on | API token in `~/.config/homelab/ha.env` |
| Loxone Miniserver | see `~/.config/homelab/loxone.env` | admin | **Read-only use only** |

Credentials and webhook IDs are in `~/.config/homelab/` on the desktop,
never in the repo. If SSH says "Permission denied", check `ssh -v` first:
the key has a passphrase and the agent may just be empty.

## Changes and deploys

- **Commit and open PRs freely** for finished repo changes; squash-merge.
- **Merge = deploy** for Komodo stacks: `homelab-gitops` deploys changed
  stacks within 5 minutes. Don't ask the user to deploy by hand; check the
  container afterwards instead.
- **Not deployed by a merge:** VM 102 (`compose/immich`,
  `compose/gpu-exporter`), `proxmox/` (installed on the host by hand, steps
  in its README), `komodo/` itself (label `manual deploy`).
- **Home Assistant config is changed live in HA** (UI / API / websocket).
  Don't copy hand-managed HA or VM config into the repo; describe it in a
  README if it matters.
- Merge Renovate PRs one at a time (several stacks deploying at once
  crash-looped `backup-scheduler`).
- Pin image versions. A new release should be about **2 weeks old** before
  it goes in; check release notes for anything that needs a config change.
- No trailing explanatory comments on config lines. Reasons go in the PR
  description or the README.

## Safety

- **Never press the Loxone `button.hjemme`, `button.borte` or `button.ferie`
  as a test.** They switch lights house-wide, lock/unlock the front door and
  set frost on the heating.
- No setpoint or Loxone changes without an explicit yes.
- Before deleting or overwriting anything on a host, look at it and keep a
  copy (session scratchpad) so it can be put back.
- The Verisure alarm is never armed; ignore it. A locked front door is not a
  presence signal.
