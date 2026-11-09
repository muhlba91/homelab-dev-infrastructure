package main

import (
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	"github.com/muhlba91/homelab-dev-infrastructure/pkg/program"
)

// main is the entry point of the Pulumi program.
func main() {
	pulumi.Run(program.Run)
}
