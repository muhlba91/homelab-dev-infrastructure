# Homelab: Dev Infrastructure

[![Build status](https://img.shields.io/github/actions/workflow/status/muhlba91/homelab-dev-infrastructure/pipeline.yml?style=for-the-badge)](https://github.com/muhlba91/homelab-dev-infrastructure/actions/workflows/pipeline.yml)
[![License](https://img.shields.io/github/license/muhlba91/homelab-dev-infrastructure?style=for-the-badge)](LICENSE.md)

This repository contains the automation for the [NixOS](https://nixos.org) dev hosts: central development VMs for
remote workspaces ([Coder](https://coder.com)) and long-running agents, using [Pulumi](http://pulumi.com). It follows
the layout and tooling of [homelab-router-infrastructure](https://github.com/muhlba91/homelab-router-infrastructure).

For each enabled host, it creates the deploy SSH key, the host's SSH host key, the GitHub machine key (authentication
and commit signing) and, if the host runs Coder, Coder's admin password and the backup credentials, and renders the host's `vars.nix` which the
NixOS configuration consumes.

The plan and the decision log: [plan.md](plan.md).

---

## Repository Layout

- [infrastructure/](infrastructure/): the Pulumi program (Go) that creates the per-host resources and renders the host
  data
- [nix/](nix/): the NixOS configuration (a flake): `modules/` (one module set for every host; the vars schema in
  `modules/options/`), `hardware/` (hardware profiles), `coder/templates/` (Coder templates shipped with the system),
  `tests/` (checks, eval tests, fixtures), `host`, `nx` and its image (`Containerfile`)
- [docs/](docs/): [Proxmox](docs/proxmox.md) (VM, sizing, first install), [install and operations](docs/install.md)
  (GitHub key, reinstall, growing the data disk), [validation](docs/validation.md), [VS Code](docs/vscode.md)

---

## Requirements

- [mise](https://mise.jdx.dev) for Go, golangci-lint, Pulumi, Terraform and tflint (the Coder templates:
  `mise run lint:templates`)
- [podman](https://podman.io) for the NixOS configuration in [nix/](nix/) (or a local [Nix](https://nixos.org/download/))

---

## Creating the Infrastructure

The stack `prod` uses the Pulumi Cloud backend and Google Cloud KMS (`tuxnet-385112`) as its secrets provider:

```bash
cd infrastructure
pulumi stack init prod --secrets-provider \
  gcpkms://projects/tuxnet-385112/locations/europe/keyRings/infrastructure-encryption/cryptoKeys/infrastructure-encryption
pulumi up
```

`pulumi up` writes the host data to `infrastructure/outputs/` (and the bucket):

| File | Content |
| --- | --- |
| `outputs/hosts/<host>/vars.nix` | the host data (no secrets; the flake's `hosts` input) |
| `outputs/keys/<host>/deploy-key` | private SSH key of the `deploy` user (stays on the workstation / bucket) |
| `outputs/keys/<host>/secrets/ssh-host-key` | the host's pinned SSH host key |
| `outputs/keys/<host>/secrets/github-ssh-key` | the GitHub machine key (owned by the host's user) |
| `outputs/keys/<host>/secrets/coder-admin-password` | Coder's first (admin) user (hosts with Coder) |
| `outputs/keys/<host>/secrets/restic-password` | the password of the host's restic repositories (hosts with Coder) |
| `outputs/keys/<host>/secrets/restic-s3` | the S3 keys of the host's backup application, an environment file (hosts with Coder) |

Stack output `hosts.<host>`:

| Key | Content |
| --- | --- |
| `keys.deploy.public`, `keys.host.public` | the public deploy key and host key (plain) |
| `keys.github.public` | the public GitHub machine key (plain; registered on GitHub by hand: [install.md](docs/install.md)) |
| `coder.admin` | Coder's first user: `username`, `email`, `password` (secret; hosts with Coder) |

---

## Environment Variables

| Variable | Purpose |
| --- | --- |
| `SCW_ACCESS_KEY`, `SCW_SECRET_KEY`, `SCW_DEFAULT_REGION` | the Scaleway bucket the host data is uploaded to |
| `SCW_ORGANIZATION_ID`, `SCW_PROJECT_ID` | required: the organization and project of the backup applications (the buckets' project; the provider's own `SCW_DEFAULT_*` are not used) |
| `GOOGLE_APPLICATION_CREDENTIALS` (or `gcloud auth application-default login`) | the secrets provider (Cloud KMS) |

Locally they live in `local.env` (git-ignored).

---

## Configuration

### Bucket

`homelab-dev-infrastructure:bucketId`: the Scaleway bucket; the files go below `dev-infrastructure/<stack>/`.

`homelab-dev-infrastructure:backupBucketId`: the backup bucket; the restic repositories go below
`dev/<host>/<application>/`. Each host with Coder gets a Scaleway IAM application with object storage access in the
project `SCW_PROJECT_ID`, which holds the bucket (Scaleway IAM cannot limit it to a path).

### Host YAML

One file per host in [infrastructure/assets/hosts/](infrastructure/assets/hosts/), named
`[<order>-]<name>.yml` (the order decides the deploy order; categories as in the router repo: `0xx` test systems,
`1xx` OVH, `2xx` Hetzner, `9xx` physical sites). Every field is documented in
[infrastructure/assets/templates/host.yml](infrastructure/assets/templates/host.yml). A host is disabled unless its
file says `enabled: true`; unknown keys are errors.

### SSH Keys

The static public keys in [infrastructure/assets/ssh/](infrastructure/assets/ssh/) (`*.pub`) may log in as `deploy`
(plus the host's generated deploy key) and as the host's user.

---

## NixOS Hosts

From `nix/` (everything runs through `./nx`, in podman on the Mac):

```bash
./host hosts                    # list hosts (in deploy order)
./host check                    # flake checks: lint, deploy schema, eval tests, every host
./host install <host> <ip>      # first install / reinstall (wipes the OS disk, keeps /data)
./host deploy <host>            # push secrets, back up, then deploy-rs (magic rollback)
./host health <host>            # failed units, data disk usage, pending reboot
./host ssh <host> [command]     # SSH as deploy
```

Without `infrastructure/outputs/` (or `OUTPUTS=<dir>`), the commands use the fixtures in `nix/tests/hosts/`.

### What runs on a host

- **Storage:** the OS disk (disko, wiped by every install) and the data disk at `/data` (homes, Coder, PostgreSQL;
  never touched by an install, grows with the disk).
- **The user:** pinned uid, home on `/data`, linger, SSH keys only, no sudo; git signs every commit with the GitHub
  machine key.
- **Development environment:** nix-ld (prebuilt runtimes, the VS Code Server), envfs, mise (from nixos-unstable: the
  repositories require a newer version than the release ships), direnv, `gh`, `vault` and the usual CLI tools.
- **Docker** (`docker.enabled`): rootless, a daemon per user as a systemd user unit (data in the home on `/data`);
  nobody is in the `docker` group. Published ports bind to `127.0.0.1` unless a port names an address, and the
  firewall blocks the rest anyway; `docker.trustedPorts` (e.g. `8000-8999`) opens ports to the trusted networks
  for containers published on the host's address (`-p 0.0.0.0:8080:80`). `DOCKER_HOST` is set for shells and user units (testcontainers works). A deploy
  never restarts the daemon (its containers would stop): `systemctl --user restart docker` picks up a new version.
  Unused images and build cache older than two weeks are pruned weekly (volumes are kept).
- **Coder** (`coder.enabled`): runs as the user with the built-in provisioner; workspaces are directories in
  `~/workspaces` (or `~/workspaces/<group>`, an optional parameter) with a `coder agent` user unit (`nix/coder/templates/local-dir`). A workspace clones its repository
  once, then fetches and fast-forwards a clean branch with an upstream and runs `mise install` at every start and
  hourly (`sync.sh`); local changes and other branches are never touched.
- **Backups** (hosts with Coder): Coder's database is dumped nightly to `/data/backup/coder` and backed up with restic
  to `dev/<host>/coder/` in the backup bucket (the last 3 snapshots plus one each from the previous two weeks, pruned after every backup). `./host deploy` runs the backup before every
  deploy that changes the system (`SKIP_BACKUP=1` skips it). Restore: [install.md](docs/install.md#restoring-coders-database).
- `dev-health` (`./host health`): failed units (system and the user's, a failed backup included), data disk usage,
  Coder answering, Docker running, pending reboot.

### Ports

| Port | From | Service |
| --- | --- | --- |
| 22/tcp | trusted networks | SSH (`deploy`, the host's user) |
| 3000/tcp | trusted networks | Coder (hosts with Coder) |
| `docker.trustedPorts` | trusted networks | containers published on the host's address (hosts with Docker) |

---

## Testing

```bash
cd infrastructure && make test                              # renders every host file under mocks
RENDER_DIR=/tmp/render make test && OUTPUTS=/tmp/render/outputs ../nix/host check   # the rendered hosts in Nix
cd nix && ./host check                                      # the fixtures
```

---

## Continuous Integration and Automations

- Pull requests: conform, YAMLLint, Go lint and tests, the Coder templates (`terraform fmt`, `validate` and
  `plan` failing on warnings, tflint), the Nix checks, `pulumi preview` with a `vars.nix` diff, the
  Nix checks of the rendered and the previewed hosts, a build of the host system.
- `main`: preview, Nix checks, `pulumi up`, then `./host deploy` and `./host health` for every host with
  `deploy.automated: true`.
- Renovate: Go modules, actions, the `nx` image and mise tools are automerged; `flake.lock` updates and NixOS
  releases are never automerged (merging them is the moment a host changes).
