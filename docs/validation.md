# Host validation

Run after an install and after changes that touch the base system. `./host health <host>` covers the automatic part
(failed units, data disk usage, pending reboot).

## Phase 1

- [ ] `./host install` brings up the VM from the ISO; `./host deploy <host>` is a no-op when nothing changed
- [ ] `./host ssh <host>` works with the pinned host key; `ssh <user>@<address>` works with the YubiKey
- [ ] `/data` is mounted (`findmnt /data`), the home is `/data/home/<user>`, owned by the pinned uid
- [ ] `loginctl show-user <user> -p Linger` is `yes`
- [ ] the firewall: SSH from the trusted networks only (`nft list ruleset`)
- [ ] VS Code Remote-SSH from the Mac opens a folder on the host
- [ ] `ssh -T git@github.com` greets you; a commit pushed from the host shows "Verified" on GitHub
- [ ] a second `./host install` keeps everything on `/data`
