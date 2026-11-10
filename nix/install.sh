#!/bin/sh
# Runs inside ./nx for `./host install`: installs <host> on root@<ip> with nixos-anywhere.
#   install.sh <host> <ip> <disk> <data label> <hosts dir> <secrets dir> <secrets target>
# nixos-anywhere cannot take --override-input, so a temporary copy of the flake points its `hosts`
# input at the host data (keep in sync with flake.nix: `url = "path:./tests/hosts";`). Pre-flight:
# the disk disko wipes must not carry the data label, and the data disk must exist. The secrets
# become --extra-files (root-owned; the activation applies owner and mode).
set -eu
host=$1 ip=$2 disk=$3 label=$4 hosts=$5 secrets=$6 target=$7

rm -rf /tmp/fl /tmp/extra
cp -a . /tmp/fl
cd /tmp/fl

# shellcheck disable=SC2087 # expanded here on purpose
ssh -o StrictHostKeyChecking=accept-new "root@$ip" sh <<EOF
if lsblk -no LABEL '$disk' | grep -qx '$label'; then echo "$disk carries the label $label: refusing to wipe it" >&2; exit 1; fi
test -e '/dev/disk/by-label/$label' || { echo "no disk with the label $label (format the data disk first)" >&2; exit 1; }
EOF

grep -q 'url = "path:./tests/hosts";' flake.nix
sed -i "s|url = \"path:./tests/hosts\";|url = \"path:$hosts\";|" flake.nix
nix flake lock

set --
if [ -d "$secrets" ]; then
  mkdir -p "/tmp/extra$target"
  cp -a "$secrets/." "/tmp/extra$target/"
  chmod 0711 "/tmp/extra$target"
  chmod 0600 "/tmp/extra$target"/*
  set -- --extra-files /tmp/extra
fi
nixos-anywhere --flake "/tmp/fl#$host" --build-on remote --phases disko,install,reboot "$@" \
  --target-host "root@$ip"
