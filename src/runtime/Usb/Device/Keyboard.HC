U16 UsbModSet1[8] = {
    0x001d, 0x002a, 0x0038, 0xe05b, 0xe01d, 0x0036, 0xe038, 0xe05c
};

U16 UsbKeySet1[101] = {
    0x00, 0x00, 0x00, 0x00, 0x1E, 0x30, 0x2E, 0x20, 0x12, 0x21, 0x22, 0x23, 0x17, 0x24, 0x25, 0x26,
    0x32, 0x31, 0x18, 0x19, 0x10, 0x13, 0x1F, 0x14, 0x16, 0x2F, 0x11, 0x2D, 0x15, 0x2C, 0x02, 0x03,
    0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x1C, 0x01, 0x0E, 0x0F, 0x39, 0x0C, 0x0D, 0x1A,
    0x1B, 0x2B, 0x2B, 0x27, 0x28, 0x29, 0x33, 0x34, 0x35, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E, 0x3F, 0x40,
    0x41, 0x42, 0x43, 0x44, 0x57, 0x58, 0xE02A, 0x46, 0x00, 0xE052, 0xE047, 0xE049, 0xE053, 0xE04F,
    0xE051, 0xE04D, 0xE04B, 0xE050, 0xE048, 0x45, 0xE035, 0x37, 0x4A, 0x4E, 0xE01C, 0x4F, 0x50, 0x51,
    0x4B, 0x4C, 0x4D, 0x47, 0x48, 0x49, 0x52, 0x53, 0x56
};

I64 UsbPrevLastKey()
{
    I64 i = 7;
    I64 sc = 0;
    while (!(sc = usb.kb->last_report[i--]) && i > 1)
        ;
    return sc;
}

I64 UsbCurrLastKey()
{
    U8* report = usb.kb->report;
    I64 i = 7;
    I64 sc = 0;
    while (!(sc = report[i--]) && i > 1)
        ;
    return sc;
}

U0 UsbMakeKey(I64 c)
{
    if ((c >> 8) == 0xe0) {
        FifoU8Ins(kbd.fifo2, 0xe0);
    }
    FifoU8Ins(kbd.fifo2, c & 0xff);
}

U0 UsbBreakKey(I64 c)
{
    if ((c >> 8) == 0xe0) {
        FifoU8Ins(kbd.fifo2, 0xe0);
    }
    FifoU8Ins(kbd.fifo2, (c & 0xff) | 0x80);
}

U0 (*_KbdHndlr)() = &KbdHndlr;

U0 UsbKbdTypematic()
{
    if (!usb.kb->timestamp) {
        return;
    }
    if (cnts.jiffies >= usb.kb->next_repeat) {
        UsbMakeKey(UsbKeySet1[UsbPrevLastKey]);
        usb.kb->next_repeat += 32;
    }
}

Bool UsbKeyIsDown(I64 k)
{
    U8* report = usb.kb->report;
    I64 i;
    for (i = 2; i < 8; i++) {
        if (report[i] == k) {
            return TRUE;
        }
    }
    return FALSE;
}

Bool UsbKeyWasDown(I64 k)
{
    I64 i;
    for (i = 2; i < 8; i++) {
        if (usb.kb->last_report[i] == k) {
            return TRUE;
        }
    }
    return FALSE;
}

U0 UsbKbdUpdateMod(I64 pm, I64 nm)
{
    I64 i;
    for (i = 0; i < 4; i++) {
        if (!(pm & (1 << i)) && nm & (1 << i)) {
            UsbMakeKey(UsbModSet1[i]);
        }
        if (pm & (1 << i) && !(nm & (1 << i))) {
            UsbBreakKey(UsbModSet1[i]);
        }
        if (!(pm & (1 << (i + 4))) && nm & (1 << (i + 4))) {
            UsbMakeKey(UsbModSet1[i + 4]);
        }
        if (pm & (1 << (i + 4)) && !(nm & (1 << (i + 4)))) {
            UsbBreakKey(UsbModSet1[i + 4]);
        }
    }
}

U0 UsbKbdUpdate()
{
    Bool pressed = FALSE;
    U8* report = usb.kb->report;
    I64 i;
    I64 pk, nk;
    I64 pm, nm;

    pm = usb.kb->last_report[0];
    nm = report[0];
    if (pm != nm) {
        UsbKbdUpdateMod(pm, nm);
    }

    for (i = 2; i < 8; i++) {
        pk = usb.kb->last_report[i];
        nk = report[i];
        if (pk && !UsbKeyIsDown(pk)) {
            UsbBreakKey(UsbKeySet1[pk]);
            if (pk == UsbPrevLastKey) {
                usb.kb->timestamp = 0;
            }
        }
        if (nk && !UsbKeyWasDown(nk)) {
            UsbMakeKey(UsbKeySet1[nk]);
            pressed = TRUE;
        }
    }

    if (pressed) {
        usb.kb->timestamp = cnts.jiffies;
        usb.kb->next_repeat = usb.kb->timestamp + 500;
    }
}

U0 _KbdMsHndlr()
{
    if (usb.kb) {
        U8* report = usb.kb->report;
        if (MemCmp(&usb.kb->last_report, report, 8)) {
            UsbKbdUpdate;
        } else {
            UsbKbdTypematic;
        }
        MemCpy(&usb.kb->last_report, report, 8);
    }

    while (FifoU8Cnt(kbd.fifo2)) {
        _KbdHndlr();
    }
}

U0 _KbdLEDsSet(I64 sc)
{
    U8* buf = usb.kb->ctrl_buf;
    buf[0] = (Bt(&sc, SCf_NUM) << 0) | (Bt(&sc, SCf_CAPS) << 1) | (Bt(&sc, SCf_SCROLL) << 2);

    U64 buf_phys = buf;
    XhciEp0Enqueue(usb.kb, 0x21 | (0x09 << 8) | (0x0200 << 16), 0x0000 | (1 << 16), 8, (2 << 10) | (1 << 6) | (3 << 16));
    XhciEp0Enqueue(usb.kb, buf_phys.u32[0], buf_phys.u32[1], 1, (3 << 10) | (0 << 16));
    XhciEp0Enqueue(usb.kb, 0, 0, 0, (4 << 10) | (1 << 5) | (1 << 16));
    XhciDoorbell(usb.kb->slot_id, 1);

    CXhciTrb evt;
    if (!XhciWaitEvent(32, &evt, 8000000)) {
        return;
    }
}

/*  This is needed because m (R14) gets clobbered when using
    a USB keyboard for reasons I haven't investigated yet.  */
U0 _WinKeyNavMenuPatch()
{
    U64 reg RSI tmpme = MenuTask->cur_menu->sub;
    asm {
        DU32 0x90c3ff33;
    }
}

U0 ApplyWinKeyNavMenuPatch()
{
    PatchCallRel32(&WinKeyNavMenu + 0x00e7, &_WinKeyNavMenuPatch + 0x0009);
    PatchNop(&WinKeyNavMenu + 0x00ec);
    PatchCallRel32(&WinKeyNavMenu + 0x015b, &_WinKeyNavMenuPatch + 0x0009);
    PatchNop(&WinKeyNavMenu + 0x0160);
}
