#!/usr/bin/env bash
# Workspace sync (coder_script: at every agent start and hourly while the workspace runs):
#   - clone WORKSPACE_REPO into WORKSPACE_DIR if it is set and nothing is cloned yet;
#   - fetch, then fast-forward the current branch only if the working tree is clean and the branch
#     has an upstream: never a merge, rebase or stash (local work and agents' branches stay as
#     they are; a skipped pull is only logged);
#   - mise install for every mise config in the repository (trusted: ~/workspaces is a trusted
#     path in the global mise config, `mise trust` covers configs moved in by a clone).
# Agents' git worktrees are separate directories: never touched.
set -u

dir=${WORKSPACE_DIR:?}
repo=${WORKSPACE_REPO:-}
log() { echo "workspace-sync: $*"; }

mkdir -p "$dir" && cd "$dir" || exit 1

if [ -n "$repo" ] && [ ! -e .git ]; then
  if [ -z "$(ls -A)" ]; then
    git clone --quiet "$repo" . && log "cloned $repo"
  else
    log "not cloning $repo: $dir is not empty"
  fi
fi

if [ -d .git ]; then
  git fetch --all --prune --quiet || log "fetch failed"
  branch=$(git symbolic-ref --quiet --short HEAD || true)
  if [ -z "$branch" ]; then
    log "pull skipped: detached HEAD"
  elif ! git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
    log "pull skipped: $branch has no upstream"
  elif [ -n "$(git status --porcelain)" ]; then
    log "pull skipped: local changes on $branch"
  elif [ "$(git rev-parse HEAD)" = "$(git rev-parse '@{u}')" ]; then
    log "$branch is up to date"
  elif git merge --ff-only --quiet '@{u}' 2>/dev/null; then
    log "$branch fast-forwarded to $(git rev-parse --short HEAD)"
  else
    log "pull skipped: $branch has diverged from its upstream"
  fi
fi

if command -v mise >/dev/null 2>&1; then
  find . \( -name .git -o -name node_modules -o -name .venv \) -prune -o \
    \( -name mise.toml -o -name .mise.toml \) -type f -print |
    while read -r config; do
      d=$(dirname "$config")
      if (cd "$d" && mise trust --quiet && mise install --quiet >/dev/null 2>&1); then
        log "mise install done in $d"
      else
        log "mise install failed in $d"
      fi
    done
fi
