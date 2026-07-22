class CUefi {
    U64 gop_fb_base;
    U64 gop_fb_size;
    U64 gop_fb_xres;
    U64 gop_fb_yres;
    U64 sys_tbl_ptr;
    U64 total_mem;
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

U32 gop_palette_std[COLORS_NUM] = {
    0xFF000000, 0xFF0000AA, 0xFF00AA00, 0xFF00AAAA, 0xFFAA0000, 0xFFAA00AA, 0xFFAA5500, 0xFFAAAAAA,
    0xFF555555, 0xFF5555FF, 0xFF55FF55, 0xFF55FFFF, 0xFFFF5555, 0xFFFF55FF, 0xFFFFFF55, 0xFFFFFFFF };

U0 GrUpdateGopGraphics()
{
    U64* u = CORE0_32BIT_INIT;
    U64 reg RDI dst = u[0];
    U64 reg RSI src = gr.dc2->body;
    U64 reg RDX lut = &gop_palette_std;
    no_warn dst, src, lut;
    asm {
        DU32 0x048bc931, 0x0c44888a, 0x0c6488c0, 0x10e8c1d0, 0xe00c4488, 0xf00c6488, 0xf983c1ff, 0xf3e37c10,
        0x24646f0f, 0x6f0ff3c0, 0xf3d0246c, 0x24746f0f, 0x6f0ff3e0, 0xb9f0247c, 0x00004b00, 0x066f0ff3,
        0xcc6f0f66, 0xd56f0f66, 0xde6f0f66, 0x6f0f4466, 0x380f66c7, 0x0f66c800, 0x66d00038, 0xd800380f,
        0x380f4466, 0x0f66c000, 0x0f66c16f, 0x0f66c260, 0x0f66ca68, 0x4166d36f, 0x66d0600f, 0xd8680f41,
        0x6f0f4466, 0x0f4466c0, 0x0f66c261, 0x0f66c269, 0x0f66d16f, 0x0f66d361, 0x4466cb69, 0x6607e70f,
        0x1047e70f, 0x57e70f66, 0xe70f6620, 0x8348304f, 0x834810c6, 0xff4840c7, 0x0f8175c9, 0x9090f8ae;
    }
}
PatchJmpRel32(&GrUpdateVGAGraphics, &GrUpdateGopGraphics);

U8 _PCIReadU8(I64 bus, I64 dev, I64 fun, I64 rg)
{
    U32 address = (bus << 16) | (dev << 11) | (fun << 8) | (rg & 0xFC) | 0x80000000;
    OutU32(0xcf8, address);
    return InU8(0xcfc + (rg & 3));
}

U0 _PCIWriteU8(I64 bus, I64 dev, I64 fun, I64 rg, I64 val)
{
    U32 address = (bus << 16) | (dev << 11) | (fun << 8) | (rg & 0xFC) | 0x80000000;
    OutU32(0xcf8, address);
    OutU8(0xcfc + (rg & 3), val);
}

U0 _PCIWriteU16(I64 bus, I64 dev, I64 fun, I64 rg, I64 val)
{
    U32 address = (bus << 16) | (dev << 11) | (fun << 8) | (rg & 0xFC) | 0x80000000;
    OutU32(0xcf8, address);
    OutU16(0xcfc + (rg & 2), val);
}

U0 _PCIWriteU32(I64 bus, I64 dev, I64 fun, I64 rg, I64 val)
{
    U32 address = (bus << 16) | (dev << 11) | (fun << 8) | (rg & 0xFC) | 0x80000000;
    OutU32(0xcf8, address);
    OutU32(0xcfc, val);
}

I64 _PCIClassFind(I64 class_code, I64 n)
{
    I64 res = 0;
    I64 b, d, f;
    for (b = 0; b < sys_pci_busses; b++) {
        for (d = 0; d < 32; d++) {
            for (f = 0; f < 8; f++) {
                if (PCIReadU32(b, d, f, 8) >> 8 == class_code) {
                    n--;
                    if (n < 0) {
                        res.u8[2] = b;
                        res.u8[1] = d;
                        res.u8[0] = f;
                        return res;
                    }
                }
            }
        }
    }
    return -1;
}
PatchJmpRel32(&PCIReadU8, &_PCIReadU8);
PatchJmpRel32(&PCIWriteU8, &_PCIWriteU8);
PatchJmpRel32(&PCIWriteU16, &_PCIWriteU16);
PatchJmpRel32(&PCIWriteU32, &_PCIWriteU32);
PatchJmpRel32(&PCIClassFind, &_PCIClassFind);
