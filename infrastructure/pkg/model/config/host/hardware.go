package host

// HardwareConfig defines the hardware configuration for a host.
type HardwareConfig struct {
	// Profile is the hardware profile of the host: a file in nix/hardware/ (e.g. qemu: any x86_64 VM).
	Profile string `yaml:"profile"`
	// Disk is the OS disk of the host (wiped by every install). With a data disk attached, its stable
	// /dev/disk/by-id/ path: /dev/sdX names are not stable with two disks.
	Disk string `yaml:"disk"`
}
