# Homelab: Dev Infrastructure

[![Build status](https://img.shields.io/github/actions/workflow/status/muhlba91/homelab-dev-infrastructure/pipeline.yml?style=for-the-badge)](https://github.com/muhlba91/homelab-dev-infrastructure/actions/workflows/pipeline.yml)
[![License](https://img.shields.io/github/license/muhlba91/homelab-dev-infrastructure?style=for-the-badge)](LICENSE.md)

[NixOS](https://nixos.org) development VMs for remote workspaces ([Coder](https://coder.com)) and long-running
agents. Built like [homelab-router-infrastructure](https://github.com/muhlba91/homelab-router-infrastructure): a
[Pulumi](https://pulumi.com) program generates each host's keys, secrets and `vars.nix`; a NixOS flake describes the
machine; `./host` installs and deploys it.

---

## Repository Layout

- [infrastructure/](infrastructure/): the Pulumi program (Go); host files in `assets/hosts/`
- [nix/](nix/): the flake: `modules/` (vars schema in `modules/options/`), `hardware/`, `coder/templates/`,
  `tests/`, and the `host` and `nx` scripts
- [docs/](docs/): [Proxmox and first install](docs/proxmox.md), [operations](docs/install.md),
  [validation](docs/validation.md), [VS Code](docs/vscode.md)

## Requirements

- [mise](https://mise.jdx.dev) (Go, Pulumi, Terraform, fnox, …), `jq`, `gh`
- [podman](https://podman.io) or a local [Nix](https://nixos.org/download/) for `nix/`
- [pre-commit](https://pre-commit.com): `pre-commit install --hook-type pre-commit --hook-type commit-msg`

---

## Pulumi

The stack `prod` uses Pulumi Cloud and Cloud KMS as its secrets provider:

```bash
cd infrastructure
pulumi stack init prod --secrets-provider \
  gcpkms://projects/tuxnet-385112/locations/europe/keyRings/infrastructure-encryption/cryptoKeys/infrastructure-encryption
```

Per enabled host, `pulumi up` creates the deploy SSH key, the SSH host key and the GitHub machine key; with Coder the
admin password and the restic credentials (with `coder.oidc` also the OIDC client secret); with the Vault Agent an
AppRole secret ID. It writes them and the host's `vars.nix` to `infrastructure/outputs/` and the bucket. Stack output
`hosts.<host>`: `keys.{deploy,host,github}.public` and `coder.admin` (secret; the bootstrap admin `admin`,
`admin@<host>.<domain>`).

### Credentials

| Variable | Purpose |
| --- | --- |
| `SCW_ACCESS_KEY`, `SCW_SECRET_KEY`, `SCW_DEFAULT_REGION` | the bucket for the host data |
| `SCW_ORGANIZATION_ID`, `SCW_PROJECT_ID` | the project of the backup buckets and IAM applications |
| `GOOGLE_APPLICATION_CREDENTIALS` | Cloud KMS |
| `VAULT_TOKEN` | reads the AppRole role IDs, manages the secret IDs |

[fnox](https://fnox.jdx.dev) loads them from Vault (`fnox.toml`). CI logs in to Vault through GitHub OIDC (repository
secrets `VAULT_ADDR`, `VAULT_PATH`, `VAULT_ROLE`). Locally
(`FNOX_PROFILE=dev`) the Vault token is the machine's own and Google credentials impersonate the CI service account:

```bash
fnox exec -- pulumi preview --stack prod
fnox exec -- mise run up:vm --stack prod   # on a dev VM: leaves the secret IDs to CI
```

### Configuration

The stack config; secret values with `pulumi config set --secret`.

#### Vault

The AppRole roles `dev-infrastructure-<host>` come from github-infrastructure; this program creates their secret IDs
(rotated every 90 days).

```yaml
vault:address: the Vault URL
```

#### Buckets

```yaml
bucketId: the Scaleway bucket of the host data (below dev-infrastructure/<stack>/)
backupBucketId: the Scaleway bucket of the restic repositories (below dev/<host>/<application>/)
```

#### OIDC

Optional. The OIDC client of Coder's SSO login, for hosts with `coder.oidc`
([setup](docs/install.md#coder-sso)).

```yaml
zitadel:
  url: the issuer URL (https, no trailing slash)
  clientId: the client ID (a string: pulumi config set --path --type string zitadel.clientId)
  clientSecret: the client secret (secret: pulumi config set --path --secret zitadel.clientSecret)
```

## Adding a host

1. Copy [assets/templates/host.yml](infrastructure/assets/templates/host.yml) (every field documented) to
   `infrastructure/assets/hosts/<order>-<name>.yml` and set `enabled: true`. The order is the deploy order (`0xx`
   test, `1xx` OVH, `2xx` Hetzner, `9xx` physical); unknown keys are errors.
2. Merge: CI runs `pulumi up`.
3. Create and install the VM: [proxmox.md](docs/proxmox.md).
4. Register the GitHub machine key: [install.md](docs/install.md#github-machine-key).
5. Validate: [validation.md](docs/validation.md).

The public keys in [infrastructure/assets/ssh/](infrastructure/assets/ssh/) may log in as `deploy` and as the user.

---

## Hosts

From `nix/` (in podman unless Nix is installed; the full list is in the header of `nix/host`):

```bash
./host check                    # flake checks: lint, deploy schema, eval tests, every host
./host install <host> <ip>      # first install or reinstall (wipes the OS disk, keeps /data)
./host deploy <host>            # push secrets, back up Coder, deploy-rs with magic rollback
./host push-secrets <host>      # deliver rotated secrets only
./host health <host>            # dev-health
./host ssh <host> [command]     # SSH as deploy
```

Without `infrastructure/outputs/` (or `OUTPUTS=<dir>`), the commands use the fixtures in `nix/tests/hosts/`. Hosts
with `deploy.automated: true` are deployed by CI after every `pulumi up` on `main`.

### What runs on a host

- **Storage:** the OS disk (wiped by every install) and `/data` (homes, Coder, PostgreSQL; kept, grows with the disk).
- **User:** pinned uid, home on `/data`, linger, SSH keys only, no sudo; commits signed with the GitHub machine key.
- **Dev environment:** nix-ld, envfs, mise, direnv, `gh`, `vault`.
- **Claude Code:** Anthropic's native build in `~/.local/bin` (`latest` channel); a user timer installs it (the
  manifest's signature checked against the pinned release key, then the checksum) and runs `claude update` daily. Log
  in once by hand (`claude`, then `/login`).
- **Dotfiles** (`user.dotfiles`): a user timer applies the chezmoi repository daily (`--force`); the system zsh stays
  the fallback.
- **Docker** (`docker.enabled`): rootless, one daemon per user; ports bind to `127.0.0.1` unless published on the
  host's address and listed in `docker.trustedPorts`.
- **Coder** (`coder.enabled`): runs as the user; workspaces are directories in `~/workspaces` that sync their
  repository at start and hourly. With an https `coder.accessUrl` it sits behind the home cluster's gateway
  (`https://coder.dev.home.muehlbachler.io`, apps under `coder.wildcardAccessUrl`). Nightly restic backup of
  its database; restore: [install.md](docs/install.md#restoring-coders-database). With `coder.oidc`: SSO login
  through an OIDC provider next to the password login.
- **Paseo** (`paseo.enabled`): the agent orchestrator as a user unit (a deploy does not restart it); web UI, apps and
  API on port 6767 behind a password Pulumi generates (`secrets/paseo-env`, stack output `hosts.<host>.paseo`). With
  `paseo.hostname` behind the home cluster's gateway (`https://paseo.dev.home.muehlbachler.io`). Settings changed in
  its UI persist; agents run the user's `claude`.
- **Vault Agent** (`vault.enabled`): a short-lived host token for the user, used by `vault`, fnox and Pulumi.
- **fnox** (`vault.enabled`): `FNOX_PROFILE=dev` and a global config in `/etc/fnox` with the host's GCP key.
- **`dev-health`:** failed units, the user manager's groups, `/data` usage, Coder, the Vault token, Docker, pending
  reboot.

### Ports

| Port | From | Service |
| --- | --- | --- |
| 22/tcp | trusted networks | SSH |
| 3000/tcp | trusted networks (incl. the cluster gateway) | Coder |
| `docker.trustedPorts` | trusted networks | containers |

---

## Testing

```bash
make -C infrastructure lint test   # golangci-lint; Go tests (render every host file under mocks)
mise run lint:templates            # Coder templates
nix/host check                     # Nix checks on the fixtures
RENDER_DIR=/tmp/render make -C infrastructure test && OUTPUTS=/tmp/render/outputs nix/host check   # rendered hosts
```

## Continuous Integration

- Pull requests: commit and YAML lint, Go lint and tests, Coder templates, Nix checks (fixtures, rendered hosts, a
  host build), `pulumi preview` with a `vars.nix` diff and Nix checks of the previewed hosts. The required checks are
  these job names.
- `main`: preview and Nix checks, `pulumi up`, then `./host deploy` and `./host health` for hosts with
  `deploy.automated: true`.
- Renovate automerges patch and minor updates, except `flake.lock` and NixOS releases (merging those changes the
  hosts).
