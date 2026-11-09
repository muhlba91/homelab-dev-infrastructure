# Install and operations

## GitHub machine key

Pulumi generates one ed25519 key per host (`secrets/github-ssh-key`, readable only by the host's user): git
authenticates and signs every commit with it. The Pulumi GitHub provider has no SSH signing key resource and managing
user keys from CI would need an account-wide token, so the key is registered by hand, once per key:

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

`./host install <host> <address>` from the installer ([proxmox.md](proxmox.md), without the `mkfs` step): the OS disk
is wiped, `/data` is kept, the secrets are delivered again.

## Growing the data disk

The data disk has no partition table (formatted as a whole, [proxmox.md](proxmox.md)), and `/data` is mounted with
`autoResize`: growing the disk in Proxmox is all it takes, the filesystem follows at the next boot. ext4 grows while
mounted, so a reboot is not needed:

```bash
qm resize <vmid> scsi1 +100G                                              # on the Proxmox host
./host ssh <host> 'echo 1 | sudo tee /sys/class/block/sdb/device/rescan'  # only if lsblk still shows the old size
./host ssh <host> sudo resize2fs /dev/disk/by-label/data                  # live; or reboot (autoResize)
./host health <host>                                                      # the new usage of /data
```

Shrinking is not possible (ext4 cannot shrink while mounted, and Proxmox does not shrink disks): start generous.
The OS disk is resized the same way in Proxmox, then reinstalled (`./host install`): it is wiped by every install
anyway, and nothing on it needs to be kept.

## Data disk lost

New disk, formatted once ([proxmox.md](proxmox.md)), `./host install`, then restore Coder's database (below) and
recreate the workspaces from pushed branches.

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
