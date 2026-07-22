### src/kernel

The source files for the patches contained in `patches/kernel_dyn.c` are provided here.

If you wish to modify them, you can create a RedSea ISO image with the `HC` files, and do the following:

- `qemu-system-x86_64 -enable-kvm -m 1024 -drive file=iso/TempleOS.ISO,index=0,media=cdrom -drive file=your.ISO.C,index=1,media=cdrom`

- `Mount;` the 2nd cdrom, then `Cd("U:"); #include "Run";` and the generated `BIN` files will be saved to the directory you launched QEMU from.

You can `MemCpy` the contents of each `BIN` file to its corresponding `&Function`.