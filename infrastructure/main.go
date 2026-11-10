package main

import (
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	"github.com/muhlba91/homelab-dev-infrastructure/pkg/program"
)

func main() {
	pulumi.Run(program.Run)
}
