I built a recovery environment because Arch developers wouldn't. Well, why would they?
# LinuxRE
It's a basic recovery environment for Arch Linux. It has own scripts to recover your system.
You can find the ISO files in the SourceForge or you can build it yourself.
Note: If you can repair manually, I know you can.
This project is for those who are as lazy as I am to write commands.

## Build

Build the ISO from an Arch Linux x86_64 host with one command:

```sh
./build.sh
```

The script validates the host, profile, available disk space, and the options
supported by the installed `mkarchiso`. If `archiso` is missing, it requests
permission to install only that package with `pacman` (it does not run a full
system upgrade); `mkarchiso` is run with elevated privileges when needed.

Each run gets a separate directory under `~/linuxre-out/`, outside the source
profile, so existing ISO files are not overwritten. The ISO, its `.sha256`
checksum file, and the build log are kept there. Failed builds retain their
log and work directory for diagnosis; their paths are printed on failure, and a
successful build removes its temporary work directory. By default the script
requires 20 GiB free on both the output and effective pacman cache filesystems.
Set `MIN_BUILD_GIB` to change this estimate and `OUTPUT_DIR` to choose another
output location, for example:

```sh
MIN_BUILD_GIB=24 OUTPUT_DIR="$HOME/LinuxRE images" ./build.sh
```

Review the profile and package list before building or booting a recovery
image.

## Live-environment security

The live environment is designed for local recovery and provides automatic
console login and passwordless sudo. Treat it as a root-equivalent environment
and do not expose it to untrusted users or networks. Password-based SSH login
is disabled; key-based SSH can be used if an operator explicitly enables the
SSH service.

## Latest Version: v0.9-rc1


## LinuxRE Discord (I don't recommend to join lol)
https://discord.gg/jxjBRjNPa
