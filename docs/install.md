# Operations

## GitHub machine key

Pulumi generates one ed25519 key per host (`secrets/github-ssh-key`): git authenticates and signs every commit with
it. The Pulumi GitHub provider cannot register SSH signing keys, so register it by hand, once per key:

```bash
cd infrastructure
pulumi stack output hosts --json | jq -r '."<host>".keys.github.public' > /tmp/<host>.pub
gh ssh-key add /tmp/<host>.pub --type authentication --title "<host>"
gh ssh-key add /tmp/<host>.pub --type signing --title "<host>"
```

The key rotates yearly (`pulumi up` replaces it): register the new key the same way, deliver it
(`./host push-secrets <host>`), then remove the old one (`gh ssh-key list`, `gh ssh-key delete <id>`).

Check on the host: `ssh -T git@github.com` greets you; a commit pushed from the host shows "Verified" on GitHub.

## Reinstall

`./host install <host> <ip>` from the installer ([proxmox.md](proxmox.md), without the `mkfs` step): the OS disk
is wiped, `/data` is kept, the secrets are delivered again.

## Growing the data disk

The data disk has no partition table and `/data` is mounted with `autoResize`: grow the disk in Proxmox; the
filesystem follows at the next boot, or live:

```bash
qm resize <vmid> scsi1 +100G                                              # on the Proxmox host
./host ssh <host> 'echo 1 | sudo tee /sys/class/block/sdb/device/rescan'  # only if lsblk still shows the old size
./host ssh <host> sudo resize2fs /dev/disk/by-label/data                  # live; or reboot (autoResize)
./host health <host>                                                      # the new usage of /data
```

Disks cannot shrink: start generous. The OS disk is wiped by every install: resize it in Proxmox, then
`./host install`.

## Data disk lost

New disk, formatted once ([proxmox.md](proxmox.md)), `./host install`, then restore Coder's database (below) and
recreate the workspaces from pushed branches.

## Coder SSO

`coder.oidc: true` adds an SSO login to Coder with an OIDC provider; the password login stays (the bootstrap admin).

1. At the provider: a confidential web client (authorization code flow, client secret) with the redirect URI
   `<coder.accessUrl>/api/v2/users/oidc/callback`, and the post-logout URI `<coder.accessUrl>`. Restrict the client
   to the allowed users at the provider (Coder allows sign-ups: whoever the provider lets through gets an account).
2. The stack config `zitadel` ([README](../README.md#oidc)).

3. `coder.oidc: true` in the host file; merge (CI runs `pulumi up` and the deploy, which delivers
   `secrets/coder-oidc`).
4. Sign in with SSO at `coder.accessUrl`: the first login creates a member account. Its e-mail must differ from the
   admin's (`user.git.email`): Coder refuses an SSO login for the e-mail of a password account.
5. Make it an owner: log in as the admin (password: `pulumi stack output hosts --show-secrets`), Users, the new
   account, roles: Owner.

A rotated client secret: update the stack config, `pulumi up`, `./host push-secrets <host>` (restarts Coder).

## Restoring Coder's database

The nightly backup (`restic-backups-coder`) dumps the database to `/data/backup/coder/coder.dump` and backs it up with
restic to `dev/<host>/coder/` in the backup bucket. `restic-coder` on the host is restic with the repository and
credentials set. On the host (`./host ssh <host>`):

```bash
sudo restic-coder snapshots                                   # the snapshots
sudo restic-coder restore latest --target /tmp/restore       # the dump: /tmp/restore/data/backup/coder/coder.dump
```

A drill into a scratch database (Coder keeps running; the dump goes through stdin: the restored directories are
root-only):

```bash
sudo runuser -u postgres -- createdb coder_restore
sudo cat /tmp/restore/data/backup/coder/coder.dump | sudo runuser -u postgres -- pg_restore --no-owner -d coder_restore
sudo runuser -u postgres -- psql -d coder_restore -c 'select username from users'
sudo runuser -u postgres -- dropdb coder_restore && sudo rm -rf /tmp/restore
```

The real restore: stop Coder, recreate the database from the dump, start Coder:

```bash
sudo systemctl stop coder coder-bootstrap coder-templates
sudo runuser -u postgres -- dropdb coder && sudo runuser -u postgres -- createdb -O coder coder
sudo cat /tmp/restore/data/backup/coder/coder.dump | sudo runuser -u postgres -- pg_restore --no-owner --role=coder -d coder
sudo systemctl start coder coder-bootstrap coder-templates
```
