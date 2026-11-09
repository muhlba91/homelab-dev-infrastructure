# Vars schema: the host itself (identity, management, trusted networks), its hardware and
# system settings.
{ lib, ... }:
let
  inherit (lib) mkOption types;
  inherit (import ./types.nix { inherit lib; })
    str
    strD
    bool
    nullable
    strList
    typedD
    cidr4
    cidr6
    ;

  # Hardware profiles are the files in ../../hardware (one source of truth for the flake too).
  hardwareProfiles = map (lib.removeSuffix ".nix") (
    builtins.attrNames (builtins.readDir ../../hardware)
  );
in
{
  options.dev = {
    meta.deployable = bool true ''
      Whether this host may be deployed. Example/evaluation-only hosts set this to
      false; they get a nixosConfiguration (for CI) but no deploy-rs node.
    '';
    meta.deployAutomated = bool false ''
      Whether CI deploys this host after every `pulumi up` on main (only a deployable
      host). Off: the host is deployed by hand only (`./host deploy`). Read by the deploy
      tooling only.
    '';
    meta.deployOrder = nullable types.ints.unsigned ''
      Position in the deploy order (from the host file's name, `<order>-<name>.yml`): the hosts
      are deployed in ascending order, hosts without one last (by name). Read by the deploy
      tooling only, never by the host's configuration.
    '';

    host = {
      name = str "Short host name (also the flake output name).";
      hostname = str "Host name.";
      domain = str "DNS domain of the host (the site's domain).";
      timezone = strD "Etc/UTC" "Time zone.";
    };

    mgmt = {
      address = str "Address (or name) deploy-rs/SSH use.";
      sshKeys = strList [ ] "Public keys allowed for the `deploy` user.";
      hostKey = nullable types.str ''
        The host's public SSH host key (`<type> <base64>`): sshd uses the matching private key
        from the secret `ssh-host-key`, and ./host accepts only this key for the host.
        null = sshd's own generated keys, accepted on first use.
      '';
    };

    trusted = {
      v4 = typedD (types.listOf cidr4) [ "10.0.0.0/8" ] ''
        Networks that may reach the host's services (SSH, Coder): our sites and the mesh
        (NetBird/Tailscale reach the site LAN through the routers).
      '';
      v6 = typedD (types.listOf cidr6) [
        "fc00::/7"
        "2001:678:dc0::/48"
      ] "IPv6 counterpart of trusted.v4.";
    };

    hardware = {
      profile = mkOption {
        type = types.enum hardwareProfiles;
        default = "qemu";
        description = "Hand-written hardware/boot profile: hardware/<profile>.nix (`qemu`: any x86_64 VM, BIOS or UEFI).";
      };
      disk = str ''
        The OS disk (disko; wiped by every install). With the data disk attached, its stable
        `/dev/disk/by-id/` path: `/dev/sdX` names are not stable with two disks.
      '';
    };

    system = {
      watchdog = typedD (types.strMatching "[0-9]+[smh]") "60s" ''
        Hardware watchdog timeout (`<n>s`, `<n>m`, `<n>h`; `0s` = off): systemd pets the watchdog
        device, and if the system hangs for this long, the hardware resets it. Needs a watchdog
        device (a Proxmox VM: q35 has one built in; without one, e.g. a cloud VM: `0s`).
      '';
      gc = {
        olderThan = typedD (types.strMatching "[0-9]+d") "7d" ''
          Garbage collection (daily) deletes system generations older than this (`<n>d`).
        '';
        keep = typedD types.ints.positive 3 ''
          Garbage collection keeps at most this many system generations (the newest, the
          current one included), even if they are younger than gc.olderThan; also the number
          of boot entries.
        '';
      };
    };
  };
}
