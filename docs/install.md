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

## Data disk lost

New disk, formatted once ([proxmox.md](proxmox.md)), `./host install`, then restore Coder's database (Phase 3) and
recreate the workspaces from pushed branches.
