// Package mocks provides Pulumi mocks for the program's tests: fake values for the generated resources, so the
// program runs offline.
package mocks

import (
	"github.com/pulumi/pulumi/sdk/v3/go/common/resource"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// PublicKey is the public key every mocked SSH key returns (a throw-away key; its private half does not exist).
const PublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFhl/9WAbovwuyCeVz+1yll3s5SVzWSnukMPnLs7a1ri mock"

// Mocks returns fake outputs for the resources of the program.
type Mocks struct{}

// NewResource returns the inputs of a resource plus fake values for its generated outputs.
// args: The resource's type, name and inputs.
func (Mocks) NewResource(args pulumi.MockResourceArgs) (string, resource.PropertyMap, error) {
	outputs := args.Inputs.Copy()

	switch args.TypeToken {
	case "tls:index/privateKey:PrivateKey":
		outputs["publicKeyOpenssh"] = resource.NewStringProperty(PublicKey + "\n")
		outputs["privateKeyOpenssh"] = resource.MakeSecret(resource.NewStringProperty("mock-private-key-" + args.Name))
	case "random:index/randomPassword:RandomPassword":
		outputs["result"] = resource.MakeSecret(resource.NewStringProperty("mock-password-" + args.Name))
		outputs["bcryptHash"] = resource.MakeSecret(resource.NewStringProperty("$2a$10$mock-hash-" + args.Name))
	case "scaleway:iam/apiKey:ApiKey":
		outputs["accessKey"] = resource.NewStringProperty("SCWMOCKACCESSKEY")
		outputs["secretKey"] = resource.MakeSecret(resource.NewStringProperty("mock-secret-key-" + args.Name))
	case "vault:appRole/authBackendRoleSecretId:AuthBackendRoleSecretId":
		outputs["secretId"] = resource.MakeSecret(resource.NewStringProperty("mock-secret-id-" + args.Name))
		outputs["accessor"] = resource.NewStringProperty("mock-accessor-" + args.Name)
	case "time:index/rotating:Rotating":
		outputs["rfc3339"] = resource.NewStringProperty("2026-01-01T00:00:00Z")
	}

	return args.Name + "-id", outputs, nil
}

// Call returns the arguments of a function call, plus the role ID of a looked-up AppRole role.
// args: The function's token and arguments.
func (Mocks) Call(args pulumi.MockCallArgs) (resource.PropertyMap, error) {
	outputs := args.Args.Copy()
	if args.Token == "vault:appRole/getAuthBackendRoleId:getAuthBackendRoleId" {
		outputs["roleId"] = resource.NewStringProperty("mock-role-id")
	}
	return outputs, nil
}
