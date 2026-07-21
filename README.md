# UwUEFI

A 萌え萌えキュン UEFI bootloader for TempleOS

![TempleOS running on a UEFI system with no BIOS](https://codeberg.org/0x2f22d23e/UwUEFI/raw/branch/main/screenshot.png)

### INFO

The entire bootloader is about ⅕ of the Kernel size, and provides all necessary steps to: load the TempleOS Standard ISO into a RAM disk, extract the Kernel to `BOOT_RAM_BASE` and live-patch minimal required functions to boot the system.

### HOWTO

You can grab pre-built files from [Releases](https://codeberg.org/0x2f22d23e/UwUEFI/releases), or generate them yourself using either the `.vscode` build task, or manually running `scripts/build-all`, to build a smol disk image with the bootloader and `TempleOS.ISO`, and launch a VM.

You can write the disk image to a flash drive with `dd if=build/disk.img of=/dev/sdX bs=64M status=progress && sync`,

or

Put a EFI-bootable filesystem on a flash drive, put `build/BOOTX64.EFI` in `/EFI/BOOT/`, and `iso/TempleOS.ISO` in `/` on your filesystem.

### BUILDING THE BOOTLOADER

Uncomment, comment `kernel_dyn.c`, `kernel.c`

Run `scripts/get-baseline-dump` to generate `Kernel_baseline.c`

Build the disk image

### (Optional: Coalesce the Kernel patches)

Run `scripts/make-kernel-patch` to generate `kernel.c`

Comment, uncomment `kernel_dyn.c`, `kernel.c`

Build the disk image

### BOOT OPTIONS

You can put a `boot.ini` in `/` on your filesystem to set boot time options. Use `key=value` format.

`IsoFilePath` to specify a full path to TempleOS.ISO

`MaxTotalMemory` to specify total memory limit in MiB (useful on bare-metal to workaround crashes)