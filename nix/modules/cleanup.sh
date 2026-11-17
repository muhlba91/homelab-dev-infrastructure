# shellcheck shell=bash
# dev-cleanup (cleanup.nix prepends the host's settings; writeShellApplication adds errexit, nounset,
# pipefail): prunes what builds and agents pile up in the user's home. `--dry-run` (or
# CLEANUP_DRY_RUN=1) shows what would go. Settings from the environment:
#   CLEANUP_DAYS                              age for Docker data, Pulumi plugins, logs, agent state
#                                             and mise's download cache
#   CLEANUP_DOCKER, _MISE, _CACHES, _LOGS     1 = run that section (_LOGS: logs and agent state)
#   CLEANUP_CACHE_MAX_MB, CLEANUP_CACHE_PATHS caches (':'-separated, relative to $HOME) and their limit
#   CLEANUP_LOG_GLOBS                         log files (':'-separated, relative to $HOME, each
#                                             `<dir>/<file glob>`)
#   CLEANUP_AGENT_STATES                      Coder agents' state dirs (relative to $HOME; empty: none)
# Every section runs; a failed one fails the run at the end (a failed user unit: dev-health warns).

dry=
if [ "${CLEANUP_DRY_RUN:-}" = 1 ]; then dry=1; fi
case $#:${1:-} in
  0:) ;;
  1:--dry-run) dry=1 ;;
  *)
    echo "usage: dev-cleanup [--dry-run]" >&2
    exit 2
    ;;
esac
days=${CLEANUP_DAYS:?}
[[ $days =~ ^[1-9][0-9]{0,4}$ ]] || {
  echo "CLEANUP_DAYS=$days: must be a number of days >= 1" >&2
  exit 2
}
age_min=$((days * 1440))
section=
rc=0

say() { printf '%s: %s\n' "$section" "$*"; }

docker_section() {
  # The user manager sets it; a shell without XDG_RUNTIME_DIR (sudo -i) may not.
  export DOCKER_HOST="${DOCKER_HOST:-unix:///run/user/$(id -u)/docker.sock}"
  if [ -n "$dry" ]; then
    say "would prune unused images, stopped containers, networks and build cache older than ${days}d, then unused anonymous volumes"
    docker system df
    return
  fi
  docker system prune --all --force --filter "until=$((days * 24))h"
  # Anonymous volumes only (named ones are kept), including those of the containers just pruned.
  docker volume prune --force
}

mise_section() {
  cd "$HOME"
  export MISE_CACHE_PRUNE_AGE="${days}d"
  if [ -n "$dry" ]; then
    mise prune --dry-run
    mise cache prune --dry-run
    return
  fi
  mise prune --yes
  mise cache prune
}

# Pulumi touches a plugin's .lastused whenever it loads the plugin.
pulumi_plugins() {
  local dir=${PULUMI_HOME:-$HOME/.pulumi}/plugins f p
  [ -d "$dir" ] || return 0
  find "$dir" -maxdepth 1 -name '?*.lastused' -mmin "+$age_min" -print0 |
    while IFS= read -r -d '' f; do
      p=${f%.lastused}
      say "pulumi plugin ${p##*/}: unused for more than ${days}d"
      if [ -z "$dry" ]; then rm -rf -- "$p" "$f" "$p.lock"; fi
    done
}

caches_section() {
  local max=${CLEANUP_CACHE_MAX_MB:?} rel d mb
  local -a paths
  [[ $max =~ ^[1-9][0-9]{0,7}$ ]] || {
    say "CLEANUP_CACHE_MAX_MB=$max: must be a number >= 1"
    return 1
  }
  pulumi_plugins
  IFS=: read -ra paths <<<"${CLEANUP_CACHE_PATHS:-}"
  for rel in "${paths[@]}"; do
    d=$HOME/$rel
    [ -d "$d" ] || continue
    # A file a running build removes makes du fail: the size it printed still counts.
    mb=$(du -sm -- "$d" 2>/dev/null | cut -f1 || true)
    if [ "${mb:-0}" -gt "$max" ]; then
      if [ -n "$dry" ]; then
        say "$rel: $mb MiB > $max MiB, would clear"
      else
        say "$rel: $mb MiB > $max MiB, clearing"
        # The Go module cache is read-only.
        chmod -R u+w -- "$d"
        rm -rf -- "$d"
      fi
    else
      say "$rel: ${mb:-0} MiB"
    fi
  done
}

logs_section() {
  local g f
  local -a globs
  IFS=: read -ra globs <<<"${CLEANUP_LOG_GLOBS:-}"
  for g in "${globs[@]}"; do
    [ -d "$HOME/${g%/*}" ] || continue
    find "$HOME/${g%/*}" -maxdepth 1 -type f -name "${g##*/}" -mmin "+$age_min" -print0 |
      while IFS= read -r -d '' f; do
        say "${f#"$HOME"/}: older than ${days}d"
        if [ -z "$dry" ]; then rm -f -- "$f"; fi
      done
  done
  agent_states
}

# A Coder agent's state (logs, script data) without its unit (the workspace is deleted or
# stopped) and unchanged for the age; a start recreates it.
agent_states() {
  local rel=${CLEANUP_AGENT_STATES:-} d recent
  [ -n "$rel" ] && [ -d "$HOME/$rel" ] || return 0
  for d in "$HOME/$rel"/*/; do
    d=${d%/}
    [ -d "$d" ] || continue
    [ ! -e "$HOME/.config/systemd/user/coder-agent-${d##*/}.service" ] || continue
    # A find error (an unreadable entry) keeps the dir.
    recent=$(find "$d" -mmin "-$age_min" -print -quit) || continue
    [ -z "$recent" ] || continue
    say "${d#"$HOME"/}: no agent unit, unchanged for ${days}d"
    if [ -z "$dry" ]; then rm -rf -- "$d"; fi
  done
}

# A section in a subshell with errexit (a failing command ends only that section). Called only as a
# plain command (not in `if` or `&&`): there bash ignores errexit inside the subshell.
run() {
  section=$1
  local status
  set +e
  (
    set -e
    case $section in
      docker) docker_section ;;
      mise) mise_section ;;
      caches) caches_section ;;
      logs) logs_section ;;
    esac
  )
  status=$?
  set -e
  if [ "$status" -ne 0 ]; then
    echo "$section: failed (exit $status)" >&2
    rc=1
  fi
}

echo "disk before: $(df -h --output=used,avail "$HOME" | tail -1)"
for s in docker mise caches logs; do
  flag=CLEANUP_${s^^}
  if [ "${!flag:-0}" != 1 ]; then continue; fi
  run "$s"
done
if [ -z "$dry" ]; then echo "disk after: $(df -h --output=used,avail "$HOME" | tail -1)"; fi
exit "$rc"
