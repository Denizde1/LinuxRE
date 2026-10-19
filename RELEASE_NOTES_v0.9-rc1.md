# LinuxRE v0.9-rc1

This is an unpublished release-candidate preparation. No GitHub release or
remote tag has been created.

## Changes

- Isolated recovery temporary data in a private, uniquely allocated directory;
  cleanup no longer trusts the caller's generic `TMP` environment variable.
- Hardened disk imaging and cloning: reject symlink/non-regular image
  destinations, prevent source/target parent-child overlap for disk clones,
  refuse writes to mounted target devices or mounted child partitions, keep
  image/restore mapfiles beside their data for resume, and require a persistent
  mapfile path for disk clones.
- Fixed system diagnostics menu entries to load and invoke the diagnostics
  functions they expose.
- Run recovery report generation with the required privileges and treat
  report-write or permission failures as failures instead of reporting success.
- Made NetworkManager the sole enabled network manager, removed the unused
  standalone iwd dependency, and removed stale activation links for networkd,
  cloud-init, VM guest, and PC/SC services.
- Preserved package-integrity findings when `pacman -Qkk` returns status 1,
  including in the diagnostic report.
- Detect classic kernels under `/boot` when the EFI System Partition is mounted
  separately.
- Treat e2fsck's documented "errors corrected" and "reboot required" status
  bits as repair results, then verify the filesystem read-only.
- Routed the interactive filesystem check menu through the read-only checker,
  removing its prior automatic FAT repair and `ntfsfix` side effects.
- Made the full target-system upgrade in Automatic Repair opt-in instead of
  running it unconditionally before every repair.
- Removed the unused `memdisk` initramfs hook; the UEFI systemd-boot profile
  does not ship `memdiskfind`, and the hook made initramfs generation fail.
- Disabled password-based SSH and remote root login because the live image
  documents a public default account password and grants passwordless sudo.
- Made interactive menus exit cleanly on end-of-input and aligned version
  reporting with `0.9-rc1`.

## Validation and limitations

The repository regression script includes mocked checks for cleanup isolation,
device-tree overlap/mount detection, package-integrity status handling,
kernel placement, symlink destinations, and SSH/version configuration. These
tests do not perform writes to real block devices.

LinuxRE remains UEFI-only. Btrfs checking is read-only and automatic Btrfs,
XFS, VFAT, exFAT, and NTFS repair is not provided by the automatic-repair
workflow. Hardware recovery, firmware/NVRAM behavior, and booting on physical
systems require separate validation.

The ISO must be built and boot-tested before this release candidate is
considered ready. No real-device recovery operation was run as part of this
audit.
