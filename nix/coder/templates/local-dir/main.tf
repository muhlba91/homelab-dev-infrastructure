# local-dir: a workspace is a directory in ~/workspaces[/<group>]/<folder> plus a `coder agent` in a systemd
# user unit of the host's user (local-exec runs as that user; deploys never restart the unit, linger
# restores it after a reboot). Stop removes the unit; delete removes the directory.
# <folder>: the folder parameter, else the repository's name, else the workspace name (which then only
# names the workspace in Coder and its agent unit).

terraform {
  # terraform_data needs 1.4.
  required_version = ">= 1.4"
  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.20.0"
    }
  }
}

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}

data "coder_parameter" "repo" {
  name         = "repo"
  display_name = "Repository"
  description  = "Optional repository to clone (e.g. git@github.com:owner/repo.git); fast-forwarded while the working tree is clean. Its name is the default folder name."
  type         = "string"
  default      = ""
  mutable      = false
  validation {
    regex = "^([^\\s']*[/:][A-Za-z0-9][A-Za-z0-9._-]*/?)?$"
    error = "A git URL whose last path segment is a repository name (letters, digits, '.', '_', '-'), or empty."
  }
}

data "coder_parameter" "folder" {
  name         = "folder"
  display_name = "Folder"
  description  = "Optional: the workspace's folder name in ~/workspaces[/<group>]. Default: the repository's name, else the workspace name."
  type         = "string"
  default      = ""
  mutable      = false
  validation {
    regex = "^([A-Za-z0-9][A-Za-z0-9._-]*)?$"
    error = "Letters, digits, '.', '_' and '-', starting with a letter or digit (or empty: the default)."
  }
}

# Immutable (like repo and folder): the directory follows from them, and a changed directory would be a
# new (empty) one.
data "coder_parameter" "group" {
  name         = "group"
  display_name = "Group"
  description  = "Optional: a subfolder of ~/workspaces to put the workspace in, at most two levels (e.g. homelab or homelab/home-assistant): lowercase letters, digits, '.', '_' and '-'."
  type         = "string"
  default      = ""
  mutable      = false
  validation {
    regex = "^([a-z0-9][a-z0-9._-]*(/[a-z0-9][a-z0-9._-]*)?)?$"
    error = "One or two folder levels separated by '/', each lowercase letters, digits, '.', '_' and '-', starting with a letter or digit (or empty: no group)."
  }
}

locals {
  name     = lower(data.coder_workspace.me.name)
  group    = data.coder_parameter.group.value
  repo     = data.coder_parameter.repo.value
  repo_dir = local.repo == "" ? "" : trimsuffix(regex("([^/:]+)/?$", local.repo)[0], ".git")
  folder   = coalesce(data.coder_parameter.folder.value, local.repo_dir, local.name)
  parent   = pathexpand(local.group == "" ? "~/workspaces" : "~/workspaces/${local.group}")
  dir      = "${local.parent}/${local.folder}"
  # Records that this workspace created the directory: delete removes only a directory it owns.
  marker = pathexpand("~/.local/state/coder-dirs/${data.coder_workspace.me.id}")

  unit    = "coder-agent-${local.name}"
  state   = pathexpand("~/.local/state/coder-agents/${local.name}")
  envfile = pathexpand("~/.config/coder-agents/${local.name}.env")
}

resource "coder_agent" "main" {
  os   = "linux"
  arch = data.coder_provisioner.me.arch
  dir  = local.dir

  env = {
    # Not Coder's own key (coder gitssh): the machine key in ~/.ssh/config authenticates and signs.
    GIT_SSH_COMMAND = "ssh"
    # For sync.sh.
    WORKSPACE_DIR  = local.dir
    WORKSPACE_REPO = local.repo
  }
}

# At every agent start (workspace start, VM reboot, a deploy restarting the agent).
resource "coder_script" "sync_start" {
  agent_id     = coder_agent.main.id
  display_name = "Sync"
  icon         = "/icon/git.svg"
  run_on_start = true
  script       = file("${path.module}/sync.sh")
}

# Hourly while the workspace runs (Coder's cron has a seconds field).
resource "coder_script" "sync_hourly" {
  agent_id     = coder_agent.main.id
  display_name = "Sync (hourly)"
  icon         = "/icon/git.svg"
  cron         = "0 0 * * * *"
  script       = file("${path.module}/sync.sh")
}

# The directory: created on the first start, destroyed only when the workspace is deleted (empty
# group folders go with their last workspace).
resource "terraform_data" "dir" {
  # Only the directory and its marker (a changed input would replace the resource: rm -rf of the old
  # directory).
  input = {
    dir    = local.dir
    marker = local.marker
  }

  # An existing directory belongs to another workspace (or is left over): fail instead of sharing it,
  # since deleting either workspace would remove the other's files.
  provisioner "local-exec" {
    command = <<-EOT
      set -eu
      if [ -e '${self.input.dir}' ]; then
        echo '${self.input.dir} already exists (another workspace?): choose another folder or group.' >&2
        exit 1
      fi
      mkdir -p '${self.input.dir}' "$(dirname '${self.input.marker}')"
      printf '%s\n' '${self.input.dir}' > '${self.input.marker}'
    EOT
  }

  # Only a directory this workspace created (marker matches); then every group folder left empty.
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      if [ "$(cat '${self.input.marker}' 2>/dev/null)" = '${self.input.dir}' ]; then
        rm -rf '${self.input.dir}'
        parent=$(dirname '${self.input.dir}')
        while [ "$(basename "$parent")" != workspaces ] && rmdir "$parent" 2>/dev/null; do
          parent=$(dirname "$parent")
        done
      else
        echo 'not removing ${self.input.dir}: not created by this workspace' >&2
      fi
      rm -f '${self.input.marker}'
    EOT
  }
}

# Shown on the workspace page (Coder has no workspace tags).
resource "coder_metadata" "dir" {
  resource_id = terraform_data.dir.id

  item {
    key   = "group"
    value = local.group == "" ? "-" : local.group
  }
  item {
    key   = "directory"
    value = local.dir
  }
  item {
    key   = "repository"
    value = data.coder_parameter.repo.value == "" ? "-" : data.coder_parameter.repo.value
  }
}

# The agent: an enabled user unit while the workspace is started. Idempotent (a start after a
# build interrupted by a Coder restart repairs it). The agent talks to the server locally, not
# through the public access URL (port: dev.coder.port).
resource "terraform_data" "agent" {
  count = data.coder_workspace.me.start_count

  input = {
    unit    = local.unit
    envfile = local.envfile
    state   = local.state
  }
  triggers_replace = [coder_agent.main.token]

  provisioner "local-exec" {
    # The token via the environment, not in the command line.
    environment = { TOKEN = coder_agent.main.token }
    command     = <<-EOT
      set -eu
      umask 077
      mkdir -p "$(dirname '${local.envfile}')" '${local.state}' ~/.config/systemd/user
      printf 'CODER_AGENT_TOKEN=%s\nCODER_AGENT_URL=%s\n' "$TOKEN" 'http://127.0.0.1:3000' > '${local.envfile}'
      cat > ~/.config/systemd/user/${local.unit}.service <<UNIT
      [Unit]
      Description=Coder agent of workspace ${local.name}
      After=network-online.target

      [Service]
      EnvironmentFile=${local.envfile}
      Environment=CODER_AGENT_LOG_DIR=${local.state}/logs
      Environment=CODER_AGENT_SCRIPT_DATA_DIR=${local.state}/scripts
      WorkingDirectory=${local.dir}
      ExecStart=/run/current-system/sw/bin/coder agent
      Restart=always
      RestartSec=5

      [Install]
      WantedBy=default.target
      UNIT
      systemctl --user daemon-reload
      systemctl --user enable '${local.unit}.service'
      systemctl --user restart '${local.unit}.service'
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      systemctl --user disable --now '${self.input.unit}.service' || true
      rm -f ~/.config/systemd/user/'${self.input.unit}'.service '${self.input.envfile}'
      systemctl --user daemon-reload
    EOT
  }

  depends_on = [terraform_data.dir]
}
