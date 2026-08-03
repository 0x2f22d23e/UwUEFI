# UwUEFI

A 萌え萌えキュン UEFI bootloader for TempleOS

![TempleOS running on some UEFI systems with no BIOS](https://git.checksum.fail/alec/UwUEFI/raw/branch/main/example.gif)

### INFO

The bootloader is about ¼ of the Kernel size, and provides the necessary steps to: load the TempleOS Standard ISO into a RAM disk, extract the Kernel to `BOOT_RAM_BASE`, and live-patch minimal required functions to boot the system.

There is *experimental* support for NVMe devices, to allow persistent storage.

### HOWTO

You can grab pre-built files from [Releases](https://git.checksum.fail/alec/UwUEFI/releases), or build them yourself using the instructions below.

You can write the disk image to a flash drive with a utility such as `dd`, or create a EFI-bootable filesystem on a flash drive, then copy `build/BOOTX64.EFI` to `/EFI/BOOT/`, and `iso/TempleOS.ISO` to `/` on your filesystem.

### BUILDING THE BOOTLOADER

You will need `Edk2`, `gcc`, `gdb` and some additional packages: `clang-tools-extra`, `mtools`, `qemu`, `qemu-system-x86-core`, `xxd`.

Use the `.vscode` build task, or manually run `scripts/build-all` to create a smol disk image with the bootloader and `TempleOS.ISO`, and launch a VM.

You will need to modify `build.edk2_path` in `scripts/build-all` to specify the path to Edk2, and the command to launch your terminal application in `gdb()`.

### (Optional: Coalesce the Kernel patches)

This can result in a *slightly* smaller file size for `build/BOOTX64.EFI`. This build option is used for [releases](https://git.checksum.fail/alec/UwUEFI/releases).

After initial build, set `build.coalesced = True` in `scripts/build-all` and re-run the build.

### BOOT OPTIONS

You can put a `boot.ini` in `/` on your filesystem to set boot time options. Use `key=value` format.

`CrcCheck=off` to skip verifying CRC32 value of `TempleOS.ISO`.

`IsoFilePath=path` to specify a full path to `TempleOS.ISO`.

`MaxTotalMemory=size` to specify total memory limit in MiB.

`MultiCore=off` to disable MultiCore start.

###### NVME RELATED OPTIONS

`NvmeAutoMount=on` to auto-mount an existing RedSea filesystem on the NVMe device. The device will mount as `T:` and the home folder will be set to `T:/Home`.

`NvmePartition=#` to specify the GPT partition number (default=2) of the RedSea filesystem to auto-mount.

You can run `NvmeInstall;` to ⚠️<span style="color:red;font-weight:bold">wipe</span>⚠️ and auto-partition the NVMe device with a 64MB EFI partition containing the bootloader and `TempleOS.ISO`, and a 1GB writable RedSea partition.

### TROUBLESHOOTING

If boot just shows a black screen, try setting `MaxTotalMemory` to a safe value, like `1024` or `2048`.

If boot crashes in `IRQ_TIMER` or displays jumbled characters everywhere, try setting `MultiCore=off`.
