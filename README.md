I built a recovery environment because Arch developers wouldn't. Well, why would they?
# LinuxRE
It's a basic recovery environment for Arch Linux. It has own scripts to recover your system.
You can find the ISO files in the SourceForge or you can build it yourself.
Note: If you can repair manually, I know you can.
This project is for those who are as lazy as I am to write commands.

## LinuxRE v0.8

LinuxRE v0.8 adds deterministic, read-only diagnostics for hardware,
storage, LUKS/LVM, Btrfs snapshots, systemd-boot entries, `fstab`, pacman
integrity/cache state, networking, target users, and journals. It can also
write a permission-restricted `linuxre-report.txt` recovery report without
including disk serial numbers, IP addresses, or user home paths.
