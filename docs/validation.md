# Host validation

Run after an install and after changes that touch the base system. `./host health <host>` covers the automatic part
(failed units, data disk usage, Coder answering, Docker running, pending reboot).

## Phase 1

- [ ] `./host install` brings up the VM from the ISO; `./host deploy <host>` is a no-op when nothing changed
- [ ] `./host ssh <host>` works with the pinned host key; `ssh <user>@<address>` works with the YubiKey
- [ ] `/data` is mounted (`findmnt /data`), the home is `/data/home/<user>`, owned by the pinned uid
- [ ] `loginctl show-user <user> -p Linger` is `yes`
- [ ] the firewall: SSH from the trusted networks only (`nft list ruleset`)
- [ ] VS Code Remote-SSH from the Mac opens a folder on the host
- [ ] `ssh -T git@github.com` greets you; a commit pushed from the host shows "Verified" on GitHub
- [ ] a second `./host install` keeps everything on `/data`

## Phase 2: rootless Docker

Run as the host's user (an SSH session sets `DOCKER_HOST`):

- [ ] `docker info` shows `rootless` and the root dir `/data/home/<user>/.local/share/docker`
- [ ] `docker run --rm hello-world` works
- [ ] `docker compose up` with a published port: `ss -ltn` shows it on `127.0.0.1` only
- [ ] a container published on `0.0.0.0` with a port in `docker.trustedPorts` is reachable from the trusted networks,
  one outside the range is not (firewall)
- [ ] a testcontainers test passes (the reaper reaches the socket)
- [ ] a deploy that changes Docker's unit prints "NOT restarting the following user units: docker.service", and
  running containers stay up

## Phase 3: Coder

- [ ] `http://<address>:3000` shows the login; the admin (`pulumi stack output hosts --show-secrets`) logs in
- [ ] the `local-dir` template is pushed (`systemctl status coder-templates`); a workspace with a repo parameter is
  created, cloned, `mise install` done
- [ ] the workspace opens from VS Code (Coder extension and plain Remote-SSH) and from the phone browser (terminal)
- [ ] a signed commit pushed from the workspace shows "Verified"; `docker run` works in it
- [ ] the workspace keeps running through a `./host deploy`, and is back after a reboot
- [ ] `sudo systemctl start restic-backups-coder` succeeds, `sudo restic-coder snapshots` lists it; the restore drill
  in [install.md](install.md#restoring-coders-database) works
- [ ] `./host deploy` of a system change prints "host: backup (restic-backups-coder.service)" first
