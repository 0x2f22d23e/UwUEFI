U0 _WinMsUpdate()
{
    if (MemCmp(&usb.ms->last_report, usb.ms->report, 4)) {
        MsUpdate(
            ClampI64(ms.pos.x + usb.ms->report[1](I8), 0, GR_WIDTH - 1),
            ClampI64(ms.pos.y + usb.ms->report[2](I8), 0, GR_HEIGHT - 1),
            ms.pos.z - usb.ms->report[3](I8),
            usb.ms->report[0] & (1 << 0),
            usb.ms->report[0] & (1 << 1));
    }
    MemCpy(&usb.ms->last_report, usb.ms->report, 4);
}