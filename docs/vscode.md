# VS Code on the Mac

Two ways to work on the host from VS Code; both reach the same directories (`~/workspaces/<workspace>`), so they can be
mixed. Mac checkouts stay separate and sync through git.

## Coder workspaces

With the [Coder extension](https://marketplace.visualstudio.com/items?itemName=coder.coder-remote): log in to the
host's Coder URL (`coder.accessUrl`), then open a workspace from the list. Without it:

```bash
coder login <coder.accessUrl>
coder config-ssh            # adds coder.<workspace> hosts to ~/.ssh/config
```

Then "Remote-SSH: Connect to Host…" → `coder.<workspace>`. The connection goes through Coder to the workspace's agent;
terminals start in the workspace directory with the workspace's environment.

## Plain Remote-SSH

`~/.ssh/config` (the dotfiles' `config.d/`):

```text
Host <host>
  HostName <address>
  User <user>
```

"Remote-SSH: Connect to Host…" → `<host>`, then open `~/workspaces/<workspace>` (or any directory). The YubiKey
authenticates; on the host, git uses the machine key for GitHub and signs every commit.

The VS Code Server and extensions with native parts run through nix-ld; a missing library goes into
`nix/modules/nix-ld.nix`.
