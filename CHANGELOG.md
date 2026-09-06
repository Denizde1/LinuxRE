# Changelog

## v0.7 - Recovery Reliability

- Made automatic repair reports distinguish initial checks, repair attempts, final verification, and overall status.
- Fixed package-integrity repair flow so affected packages are parsed, rechecked, and reported accurately.
- Added non-destructive regression coverage for final-status propagation.
- Added read-only system information and diagnostic scan screens.
- Added network diagnostics and configuration/package-list backup export.
- Added a read-only storage inspector for device, filesystem, LVM, encryption, and Btrfs information.
- Hardened temporary Btrfs inspection cleanup and preserved failed mount/LUKS/LVM cleanup state for retry/reporting.
- Preserved safe target, mount, Btrfs, ESP, kernel, initramfs/UKI, systemd, and systemd-boot handling.
- Updated the Recovery Center version to v0.7.
