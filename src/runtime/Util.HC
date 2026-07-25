class CUefi {
    U64 gop_fb_base;
    U32 gop_fb_size;
    U32 gop_fb_xres;
    U32 gop_fb_yres;
    U64 sys_tbl_ptr;
    U64 total_mem;
    U64 boot_efi_ptr;
    U32 boot_efi_size;
    U64 boot_ini_ptr;
    U32 boot_ini_size;
};

U0 (*SseOn)() = "\x55\x48\x8b\xec\x0f\x20\xc0\x66\x25\xfb\xff\x66\x0d\x02\x00\x0f\x22\xc0\x0f\x20\xe0\x66\x0d\x00\x06\x0f\x22\xe0\x5d\xc3";
U0 SseEnable()
{
    SseOn();
    I64 i;
    for (i = 1; i < mp_cnt; i++) {
        Spawn(SseOn, , , i);
    }
}
SseEnable;

U0 PatchCallRel32(U32 from, U32 to)
{
    *(from(U8*)) = 0xe8;
    *((from + 1)(I32*)) = to - from - 5;
}

U0 PatchJmpRel32(U32 from, U32 to)
{
    *(from(U8*)) = 0xe9;
    *((from + 1)(I32*)) = to - from - 5;
}

Bool IsKVM()
{
    U64 c[4];
    CPUId(0x40000000, c);
    return c[1] == 'KVMK';
}

U0 RelocateBootFiles()
{
    CUefi* u = CORE0_32BIT_INIT;
    U64 src, size;

    src = u->boot_ini_ptr;
    size = u->boot_ini_size;
    if (src && size) {
        u->boot_ini_ptr = MAlloc(size);
        MemCpy(u->boot_ini_ptr, src, size);
    }

    src = u->boot_efi_ptr;
    size = u->boot_efi_size;
    if (src && size) {
        u->boot_efi_ptr = MAlloc(size);
        MemCpy(u->boot_efi_ptr, src, size);
    }
}
RelocateBootFiles;