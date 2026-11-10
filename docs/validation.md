# Host validation

Run after an install and after changes to the base system; `./host health <host>` covers the automatic part.
Sections other than the base system apply only to hosts with that feature enabled.

## Base system

- [ ] `./host install` brings up the VM from the ISO; `./host deploy <host>` is a no-op when nothing changed
- [ ] `./host ssh <host>` works with the pinned host key; `ssh <user>@<address>` works with the YubiKey
- [ ] `/data` is mounted (`findmnt /data`), the home is `/data/home/<user>`, owned by the pinned uid
- [ ] `loginctl show-user <user> -p Linger` is `yes`
- [ ] the firewall: SSH from the trusted networks only (`nft list ruleset`)
- [ ] VS Code Remote-SSH from the Mac opens a folder on the host
- [ ] the GitHub machine key works ([install.md](install.md#github-machine-key))
- [ ] a second `./host install` keeps everything on `/data`

## Rootless Docker

Run as the host's user (an SSH session sets `DOCKER_HOST`):

- [ ] `docker info` shows `rootless` and the root dir `/data/home/<user>/.local/share/docker`
- [ ] `docker run --rm hello-world` works
- [ ] `docker compose up` with a published port: `ss -ltn` shows it on `127.0.0.1` only
- [ ] a container published on `0.0.0.0` with a port in `docker.trustedPorts` is reachable from the trusted networks,
  one outside the range is not (firewall)
- [ ] a testcontainers test passes (the reaper reaches the socket)
- [ ] a deploy that changes Docker's unit prints "NOT restarting the following user units: docker.service", and
  running containers stay up

## Coder

- [ ] the Coder URL (`coder.accessUrl`) shows the login; the admin (`pulumi stack output hosts --show-secrets`) logs in
- [ ] the `local-dir` template is pushed (`systemctl status coder-templates`); a workspace with a repo parameter is
  created, cloned, `mise install` done
- [ ] the workspace opens from VS Code (Coder extension and plain Remote-SSH) and from the phone browser (terminal)
- [ ] a signed commit pushed from the workspace shows "Verified"; `docker run` works in it
- [ ] the workspace keeps running through a `./host deploy`, and is back after a reboot
- [ ] `sudo systemctl start restic-backups-coder` succeeds, `sudo restic-coder snapshots` lists it; the restore drill
  in [install.md](install.md#restoring-coders-database) works
- [ ] `./host deploy` of a system change prints "host: backup (restic-backups-coder.service)" first

## Vault Agent and fnox

Run as the host's user:

- [ ] `vault token lookup` shows the policy `dev-infrastructure-<host>` and a TTL that keeps refreshing over a day
- [ ] `vault kv get` of a path the policy allows works; a write is denied; `vault login` does not replace the token
- [ ] `cat /var/lib/secrets/vault-secret-id` is denied
- [ ] `fnox exec` in a pilot repository works
- [ ] a rotated secret ID (`pulumi up` + `./host push-secrets <host>`) restarts the agent with no manual step

## Public Coder (cluster gateway)

- [ ] in the home cluster (apps repo, `external-services`): `kubectl -n external-services get listenerset coder-listeners`
  accepted, certificate `coder-tls-cert` ready with both names (`coder.dev.home.muehlbachler.io`,
  `*.coder.dev.home.muehlbachler.io`), both DNS records published
- [ ] `https://coder.dev.home.muehlbachler.io` logs in from the Mac and the phone (mobile data, not the mesh)
- [ ] a forwarded port (dashboard "Ports") opens under `*.coder.dev.home.muehlbachler.io`
- [ ] a workspace terminal in the browser stays open longer than an hour
- [ ] Coder's audit log shows the real client IP, not the gateway's

## Developer machine access

Run as the host's user:

- [ ] `echo $FNOX_PROFILE $FNOX_CONFIG_DIR` shows `dev /etc/fnox`, in a shell and in a workspace terminal
- [ ] `vault kv get -field=credentials dev-infrastructure/gcp-dev-<host> >/dev/null` and
  `vault kv get -field=token dev-infrastructure/pulumi-muhlba91 >/dev/null` work; another host's
  `dev-infrastructure/gcp-dev-<other>` and `gcp-dev-mac` are denied
- [ ] `vault read auth/approle/role/dev-infrastructure-<host>/role-id` works;
  `vault write -f auth/approle/role/dev-infrastructure-<host>/secret-id` is denied
- [ ] `vault token create -role=dev-infrastructure-repo-tokens -policy=github-homelab-router-infrastructure` works
  (revoke it afterwards); `-policy=github-homelab-dev-infrastructure` and `-policy=admin` are denied
- [ ] the GCP key can impersonate a CI service account (`gcloud auth print-access-token --impersonate-service-account=<ci SA>`
  with the key activated in a throw-away `CLOUDSDK_CONFIG`) and can do nothing else (e.g. list buckets denied)
- [ ] `fnox exec -- pulumi preview` works for this repository (host token) and for homelab-router-infrastructure (minted token)
- [ ] `mise run up:vm` applies a change and leaves the secret IDs untouched; `mise run up:vm --refresh` refuses
