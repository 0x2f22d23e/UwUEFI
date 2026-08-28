U0 _I2cWinMsUpdate()
{
    if (i2c.ms) {
        if (MemCmp(&i2c.ms->last_report, i2c.ms->report, 16)) {
            MsUpdate(
                ClampI64(ms.pos.x + i2c.ms->report[4](I8), 0, GR_WIDTH - 1),
                ClampI64(ms.pos.y + i2c.ms->report[5](I8), 0, GR_HEIGHT - 1),
                0,
                i2c.ms->report[3] & 1,
                i2c.ms->report[3] & 2);
            ms_hard.timestamp = GetTSC;
        }
        MemCpy(&i2c.ms->last_report, i2c.ms->report, 16);
    }
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