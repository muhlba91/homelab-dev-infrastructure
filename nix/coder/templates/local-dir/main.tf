# local-dir: a workspace is a directory in ~/workspaces plus a `coder agent` running as the host's
# user in a systemd user unit (outside NixOS: deploys never restart it, linger brings it back after
# a reboot). No containers: one mise cache and one rootless Docker for every workspace.
#
# The built-in provisioner runs as the Coder server's user (the host's user), so local-exec runs
# as that user. Stop destroys only the start-gated unit; the directory is destroyed on delete.

terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
  }
}

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

data "coder_parameter" "repo" {
  name         = "repo"
  display_name = "Repository"
  description  = "Optional: an SSH URL to clone into the workspace (git@github.com:owner/repo.git), with the machine key."
  type         = "string"
  default      = ""
  mutable      = false
}

locals {
  name    = lower(data.coder_workspace.me.name)
  dir     = pathexpand("~/workspaces/${local.name}")
  unit    = "coder-agent-${local.name}"
  state   = pathexpand("~/.local/state/coder-agents/${local.name}")
  envfile = pathexpand("~/.config/coder-agents/${local.name}.env")
}

resource "coder_agent" "main" {
  os   = "linux"
  arch = data.coder_provisioner.me.arch
  dir  = local.dir

  # The agent points git at Coder's own key (coder gitssh); the machine key in ~/.ssh/config
  # (github.com) authenticates and signs instead.
  env = {
    GIT_SSH_COMMAND = "ssh"
  }

  startup_script_behavior = "non-blocking"
  startup_script          = <<-EOT
    set -eu
    cd "${local.dir}"
    if [ -n "${data.coder_parameter.repo.value}" ] && [ ! -d .git ]; then
      git clone "${data.coder_parameter.repo.value}" .
    fi
    if command -v mise >/dev/null 2>&1 && { [ -f mise.toml ] || [ -f .mise.toml ]; }; then
      mise trust && mise install
    fi
  EOT
}

# The directory: created on the first start, destroyed only when the workspace is deleted.
resource "terraform_data" "dir" {
  input = local.dir

  provisioner "local-exec" {
    command = "mkdir -p '${self.input}'"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "rm -rf '${self.input}'"
  }
}

# The agent: an enabled user unit while the workspace is started. Idempotent (a start after a
# build interrupted by a Coder restart repairs it).
resource "terraform_data" "agent" {
  count = data.coder_workspace.me.start_count

  input = {
    unit    = local.unit
    envfile = local.envfile
    state   = local.state
  }
  triggers_replace = [coder_agent.main.token]

  provisioner "local-exec" {
    command = <<-EOT
      set -eu
      umask 077
      mkdir -p "$(dirname '${local.envfile}')" '${local.state}' ~/.config/systemd/user
      printf 'CODER_AGENT_TOKEN=%s\nCODER_AGENT_URL=%s\n' '${coder_agent.main.token}' '${data.coder_workspace.me.access_url}' > '${local.envfile}'
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
