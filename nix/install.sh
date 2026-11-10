#!/bin/sh
# install.sh <host> <ip> <disk> <data label> <hosts dir> <secrets dir> <secrets target>
# nixos-anywhere install of <host> on root@<ip>, run inside ./nx by `./host install`.
set -eu
host=$1 ip=$2 disk=$3 label=$4 hosts=$5 secrets=$6 target=$7

w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT

# disko must not wipe the data disk, and the installed system needs it.
# shellcheck disable=SC2087 # expanded here on purpose
ssh -o StrictHostKeyChecking=accept-new "root@$ip" sh <<EOF
if lsblk -no LABEL '$disk' | grep -qx '$label'; then echo "$disk carries the label $label: refusing to wipe it" >&2; exit 1; fi
test -e '/dev/disk/by-label/$label' || { echo "no disk with the label $label (format the data disk first)" >&2; exit 1; }
EOF

# nixos-anywhere takes no --override-input: a copy of the flake points its `hosts` input at the host data.
line='url = "path:./tests/hosts";'
cp -a . "$w/flake"
cd "$w/flake"
grep -qF "$line" flake.nix || { echo "install: flake.nix has no line '$line'" >&2; exit 1; }
sed -i "s|$line|url = \"path:$hosts\";|" flake.nix
nix flake lock

# The secrets as --extra-files (root-owned; the activation applies owner and mode).
set --
if [ -n "$(ls -A "$secrets" 2>/dev/null)" ]; then
  mkdir -p "$w/extra$target"
  cp -a "$secrets/." "$w/extra$target/"
  chmod 0711 "$w/extra$target"
  chmod 0600 "$w/extra$target"/*
  set -- --extra-files "$w/extra"
fi
nixos-anywhere --flake "$w/flake#$host" --build-on remote --phases disko,install,reboot "$@" \
  --target-host "root@$ip"
