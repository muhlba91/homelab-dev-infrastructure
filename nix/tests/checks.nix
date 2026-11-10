# Flake checks (`./host check`), offline; the configurations are only evaluated, never built.
#   lint          nixfmt, deadnix, statix, shellcheck, install.sh's flake line, the Coder templates
#                 against the hosts' Terraform
#   deploy-schema the deploy-rs nodes against deploy-rs' schema (its own check builds every host)
#   host-<name>   the host evaluates; `nft --check` of its ruleset in a user-space kernel (LKL)
#   eval          tests/eval.nix on the fixtures
{
  pkgs,
  lib,
  terraform,
  src,
  configurations,
  fixtures,
  deploy,
  deploySchema,
}:
let
  # A file with text of the evaluated configuration, without its store paths: they belong
  # to the hosts' system and must not become build inputs of the check.
  file = name: text: pkgs.writeText name (builtins.unsafeDiscardStringContext text);

  ruleset =
    c:
    lib.concatMapStrings (t: ''
      table ${t.family} ${t.name} {
      ${t.content}
      }
    '') (lib.attrValues (lib.filterAttrs (_: t: t.enable) c.networking.nftables.tables));

  # nft --check needs a kernel: LKL provides one in the process, libredirect the /etc
  # files nft reads (as in nixpkgs' nftables module).
  nftCheck = ''
    NIX_REDIRECTS=/etc/protocols=${pkgs.iana-etc}/etc/protocols:/etc/services=${pkgs.iana-etc}/etc/services \
    LD_PRELOAD="${pkgs.libredirect}/lib/libredirect.so ${pkgs.lklWithFirewall.lib}/lib/liblkl-hijack.so" \
      nft --check --file'';

  hostCheck =
    name: system:
    let
      c = system.config;
    in
    pkgs.runCommand "check-host-${name}"
      {
        nativeBuildInputs = [ pkgs.nftables ];
      }
      ''
        echo "ok   evaluates (${builtins.unsafeDiscardStringContext c.system.build.toplevel.drvPath})"
        ${nftCheck} ${file "ruleset.nft" (ruleset c)}
        echo "ok   nft --check"
        touch $out
      '';

  evalFailures = import ./eval.nix { inherit lib fixtures; };
in
{
  eval = pkgs.runCommand "check-eval" { } (
    if evalFailures == [ ] then
      "echo 'ok   eval tests'; touch $out"
    else
      "cat ${file "failures.json" (builtins.toJSON evalFailures)}; exit 1"
  );

  deploy-schema =
    pkgs.runCommand "check-deploy-schema"
      {
        nativeBuildInputs = [ pkgs.check-jsonschema ];
      }
      "check-jsonschema --schemafile ${deploySchema} ${file "deploy.json" (builtins.toJSON deploy)} && touch $out";

  lint =
    pkgs.runCommand "check-lint"
      {
        nativeBuildInputs = [
          pkgs.nixfmt
          pkgs.deadnix
          pkgs.statix
          pkgs.shellcheck
          pkgs.jq
          terraform
        ];
      }
      ''
        cd ${src}
        nixfmt --check $(find . -name '*.nix')
        echo "ok   nixfmt"
        deadnix --fail -- .
        echo "ok   deadnix"
        statix check .
        echo "ok   statix"
        shellcheck host nx install.sh secrets-sync.sh coder/templates/local-dir/sync.sh
        echo "ok   shellcheck"
        grep -qF 'url = "path:./tests/hosts";' flake.nix || { echo "flake.nix: the hosts url line install.sh rewrites is gone"; exit 1; }
        echo "ok   install.sh's flake line"
        # Only `terraform init` enforces required_version: offline, against placeholder binaries
        # of the providers (init installs them without running them).
        export HOME=$TMPDIR CHECKPOINT_DISABLE=1
        platform=$(terraform version -json | jq -r .platform)
        for dir in coder/templates/*/; do
          name=$(basename "$dir")
          work=$TMPDIR/templates/$name plugins=$TMPDIR/plugins/$name
          mkdir -p "$work" && cp "$dir"*.tf "$work"/
          for p in $(terraform -chdir="$work" providers | sed -n 's|.*provider\[registry\.terraform\.io/\([^]]*\)\].*|\1|p'); do
            mkdir -p "$plugins/registry.terraform.io/$p/999.0.0/$platform"
            install -m 0755 /dev/null "$plugins/registry.terraform.io/$p/999.0.0/$platform/terraform-provider-''${p#*/}_v999.0.0"
          done
          terraform -chdir="$work" init -backend=false -input=false -no-color -plugin-dir="$plugins" >"$TMPDIR/init.log" 2>&1 ||
            { cat "$TMPDIR/init.log"; echo "coder/templates/$name: terraform init fails with the hosts' Terraform ${terraform.version}"; exit 1; }
        done
        echo "ok   templates (Terraform ${terraform.version})"
        touch $out
      '';
}
// lib.mapAttrs' (
  name: system: lib.nameValuePair "host-${name}" (hostCheck name system)
) configurations
