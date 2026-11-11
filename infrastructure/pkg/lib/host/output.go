package host

import (
	"strings"

	tlsProv "github.com/pulumi/pulumi-tls/sdk/v5/go/tls"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	"github.com/muhlba91/homelab-dev-infrastructure/pkg/model/config/host"
)

// Output returns a host's part of the stack output "hosts" (empty for a disabled host):
//
//	keys: {deploy, host, github}: {public}         the public keys (plain; github is registered on GitHub by hand)
//	coder: {admin: {username, email, password}}  Coder's first user (secret; only for a host with Coder)
//	paseo: {password}                            Paseo's password (secret; only for a host with Paseo)
//
// h: The host configuration.
// data: The generated resources and files of the host.
func Output(h *host.Config, data *Data) pulumi.Map {
	output := pulumi.Map{}
	if data.DeployKey == nil {
		return output
	}

	output["keys"] = pulumi.Map{
		"deploy": publicKey(data.DeployKey),
		"host":   publicKey(data.HostKey),
		"github": publicKey(data.GitHubKey),
	}

	if data.CoderAdminPassword != nil {
		output["coder"] = pulumi.Map{
			"admin": pulumi.ToSecret(pulumi.Map{
				// As nix/modules/options/services.nix (dev.coder.admin).
				"username": pulumi.String("admin"),
				"email":    pulumi.String("admin@" + h.Name + "." + h.Network.Domain),
				"password": *data.CoderAdminPassword,
			}),
		}
	}

	if data.PaseoPassword != nil {
		output["paseo"] = pulumi.ToSecret(pulumi.Map{"password": *data.PaseoPassword})
	}

	return output
}

// publicKey returns {public: <key>}: the public key of a key pair in OpenSSH format, without the trailing newline.
// key: The key pair.
func publicKey(key *tlsProv.PrivateKey) pulumi.Map {
	public, _ := key.PublicKeyOpenssh.ApplyT(strings.TrimSpace).(pulumi.StringOutput)
	return pulumi.Map{"public": public}
}
