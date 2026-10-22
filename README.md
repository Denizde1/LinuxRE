I built a recovery environment because Arch developers wouldn't. Well, why would they?
# LinuxRE
It's a basic recovery environment for Arch Linux. It has own scripts to recover your system.
You can find the ISO files in the SourceForge or you can build it yourself.
Note: If you can repair manually, I know you can.
This project is for those who are as lazy as I am to write commands.

## Build

Build the ISO from an Arch Linux host with `archiso` installed:

```sh
sudo pacman -S archiso
sudo mkarchiso -v -w /tmp/linuxre-work -o /tmp/linuxre-out .
```

The image is written to `/tmp/linuxre-out`. Review the profile and package list
before building or booting a recovery image.

## Live-environment security

The live environment is designed for local recovery and provides automatic
console login and passwordless sudo. Treat it as a root-equivalent environment
and do not expose it to untrusted users or networks. Password-based SSH login
is disabled; key-based SSH can be used if an operator explicitly enables the
SSH service.

## Latest Version: v0.9-rc1


## LinuxRE Discord (I don't recommend to join lol)
https://discord.gg/jxjBRjNPa
