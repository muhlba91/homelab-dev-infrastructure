# local-dir: a workspace is a directory in ~/workspaces[/<group>] plus a `coder agent` in a systemd
# user unit of the host's user (local-exec runs as that user; deploys never restart the unit, linger
# restores it after a reboot). Stop removes the unit; delete removes the directory.

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
  description  = "Optional repository to clone (e.g. git@github.com:owner/repo.git); fast-forwarded while the working tree is clean."
  type         = "string"
  default      = ""
  mutable      = false
}

# Immutable: the directory follows from it, and a changed directory would be a new (empty) one.
data "coder_parameter" "group" {
  name         = "group"
  display_name = "Group"
  description  = "Optional: a subfolder of ~/workspaces to put the workspace in (e.g. hochschule-burgenland): lowercase letters, digits, '.', '_' and '-'."
  type         = "string"
  default      = ""
  mutable      = false
  validation {
    regex = "^([a-z0-9][a-z0-9._-]*)?$"
    error = "Lowercase letters, digits, '.', '_' and '-', starting with a letter or digit (or empty: no group)."
  }
}

locals {
  name   = lower(data.coder_workspace.me.name)
  group  = data.coder_parameter.group.value
  parent = pathexpand(local.group == "" ? "~/workspaces" : "~/workspaces/${local.group}")
  dir    = "${local.parent}/${local.name}"

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
    WORKSPACE_REPO = data.coder_parameter.repo.value
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

# The directory: created on the first start, destroyed only when the workspace is deleted (a group
# folder goes with its last workspace).
resource "terraform_data" "dir" {
  # Only the directory (a changed input would replace the resource: rm -rf of the old directory).
  input = local.dir

  provisioner "local-exec" {
    command = "mkdir -p '${self.input}'"
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      rm -rf '${self.input}'
      parent=$(dirname '${self.input}')
      [ "$(basename "$parent")" = workspaces ] || rmdir "$parent" 2>/dev/null || true
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
# through the public access URL.
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
