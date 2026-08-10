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
    ms.speed *= 0.95;
    I64 dd;
    if (gr.scrn_zoom != 1) {
        if (gr.continuous_scroll)
            GrScaleZoom(1.0);
        else {
            dd = (ms.pos.x - gr.sx) * gr.scrn_zoom;
            if (!(8 <= dd < GR_WIDTH - 8))
                GrScaleZoom(1.0);
            else {
                dd = (ms.pos.y - gr.sy) * gr.scrn_zoom;
                if (!(8 <= dd < GR_HEIGHT - 8))
                    GrScaleZoom(1.0);
            }
        }
    }
}

U0 _GrScaleZoom(F64 scale)
{
    F64 s = gr.scrn_zoom;
    gr.scrn_zoom = gr.scrn_zoom * scale;
    GrFixZoomScale;
    gr.sx = ms.pos.x - gr.zoomed_dc->width >> 1 / gr.scrn_zoom;
    gr.sy = ms.pos.y - gr.zoomed_dc->height >> 1 / gr.scrn_zoom;
    GrFixZoomScale;
}
PatchJmpRel32(&GrScaleZoom, &_GrScaleZoom);