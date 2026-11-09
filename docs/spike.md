# Phase 0: Coder spike

Goal: prove the Phase 3 design (Coder as the host's user, directory workspaces, built-in provisioner) before Phase 1
depends on it. Throw-away VM `hetzner-fra-dev-000` (host file `000-hetzner-fra-dev-000.yml`): the Phase 1 user setup
(pinned uid, home on the separate `/data` disk, linger, subuid ranges) plus `coder.enabled: true`. File and VM are
deleted when the spike is done.

## Setup

1. VM as in [proxmox.md](proxmox.md) (smaller: 4 cores, 8 GB, 32 GB OS disk, 32 GB data disk); set its MAC and
   address in the host file, `enabled: true`.
2. `pulumi up` (you), then `./host install hetzner-fra-dev-000 <address>`.
3. Coder at `http://<address>:3000`, admin user = the host file's user, password:
   `pulumi stack output hosts --show-secrets --json | jq -r '."hetzner-fra-dev-000".coder.admin.password'`.

## Checklist

Results of the run on 2026-11-09 (Coder v2.28.6, Terraform 1.15.3 from nixpkgs):

- [x] PostgreSQL: Coder connects as role `coder` through the peer map; data in `/data/postgresql/17`
- [x] state stays in `/data/coder` (config, cache, Terraform plugins); fix: `CHECKPOINT_DISABLE=1`, Terraform wrote
  its update-check cache to `~/.terraform.d`
- [x] `coder-bootstrap` creates the first user and `/data/coder/tokens/admin`
- [x] `coder-templates` pushes `local-dir`
- [x] the sandbox (`ProtectSystem=full`, `PrivateTmp`) does not break Terraform or the template
- [x] the provisioner reaches the user manager (`systemctl --user` from local-exec), also after a reboot
- [x] lifecycle: create, stop (unit gone, directory kept), start, delete (directory, unit and env file gone)
- [x] workspace agents are back and healthy after a VM reboot (linger, enabled user units), without a login
- [x] a start interrupted by `systemctl restart coder` leaves the workspace stopped; starting it again repairs it
- [x] two workspaces at once (separate agent state directories)
- [x] the agent's `GIT_SSH_COMMAND` is overridden (`ssh`): git uses the machine key and signs (`gpg.format = ssh`)
- [x] Terraform from nixpkgs is accepted by Coder
- [x] a workspace agent keeps running through a `./host deploy` that restarts Coder (no agent restart)
- [x] `ssh -T git@github.com` from a workspace; a signed commit pushed to `tmp-coder` shows "Verified"
- [x] VS Code on the Mac: the Coder extension and `coder config-ssh` + Remote-SSH open a workspace
- [x] the phone browser: web terminal of a workspace
- [x] `coder-bootstrap` second run is a no-op ("token valid"); fix: `coder-templates` pushed an unchanged template
  on every Coder restart, now only when the template's store path changes
- [ ] Zitadel OIDC login: deferred, configured at the end once the rest works (D41, D47)

Other findings: systemd-resolved ran LLMNR and mDNS (now off). The QEMU guest agent was inactive because the
throw-away VM has no agent device: not needed for the spike; the real VM gets `--agent 1` ([proxmox.md](proxmox.md)).

**Result: passed** (OIDC deferred). The design of Phase 3 stands; the fixes are in `nix/modules/coder.nix` and
`nix/modules/networking.nix`.

## Outcome

- passed: Phase 1 starts; the spike's fixes go into `nix/modules/coder.nix` and the template.
- failed: revise Phase 3 (fallbacks in the plan: container workspaces, code-server).
