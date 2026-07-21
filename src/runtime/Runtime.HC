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

U32 gop_palette_std[COLORS_NUM] = { 0xFF000000, 0xFF0000AA, 0xFF00AA00, 0xFF00AAAA, 0xFFAA0000, 0xFFAA00AA, 0xFFAA5500, 0xFFAAAAAA, 0xFF555555, 0xFF5555FF, 0xFF55FF55, 0xFF55FFFF, 0xFFFF5555, 0xFFFF55FF, 0xFFFFFF55, 0xFFFFFFFF };
U0 GrUpdateGopGraphics()
{
    CUefi *u = CORE0_32BIT_INIT;
    U32* p = u->gop_fb_base;
    I64 x, y, i;
    for (y = 0; y < GR_HEIGHT; y++) {
        for (x = 0; x < GR_WIDTH; x++) {
            i = (y * GR_WIDTH) + x;
            p[i] = gop_palette_std[gr.dc2->body[i]];
        }
    }
}
PatchJmpRel32(&GrUpdateVGAGraphics, &GrUpdateGopGraphics);