U32 I2cR32(I64 r)
{
    return *(i2c.mmio_base + r)(U32*);
}

U0 I2cW32(I64 r, U32 val)
{
    *(i2c.mmio_base + r)(U32*) = val;
}

I64 I2cScan()
{
    // FIXME: Parse ACPI instead of hard-coded
    return 0x001501; // Sunrise Point-LP PCH 100
}

Bool I2cSupported()
{
    // FIXME: Parse ACPI instead of hard-coded
    return PCIReadU32(I2C_PCI, 0) == 0x9d618086;
}

U0 I2cClear()
{
    U32 tmp = I2cR32(DW_IC_CLR_INTR);
    tmp = I2cR32(DW_IC_CLR_TX_ABRT);
}

Bool I2cInit1()
{
    CI2cMouse* ms = CAlloc(sizeof(CI2cMouse));
    ms->type = I2C_TYPE_MOUSE;
    ms->address = 0x15; // FIXME: Don't hardcode this?
    i2c.ms = ms;

    I2cW32(I2C_RESETS, 0x00);
    Sleep(2);

    I2cW32(I2C_RESETS, 0x07);
    I2cW32(I2C_CLOCK_GATE, 0x0F);

    I2cW32(DW_IC_CON, 0x65);
    I2cW32(DW_IC_TAR, i2c.ms->address);

    // Clock values
    I2cW32(DW_IC_FS_SCL_HCNT, 60);
    I2cW32(DW_IC_FS_SCL_LCNT, 130);
    I2cW32(DW_IC_SDA_HOLD, 30);

    I2cClear;

    I2cW32(DW_IC_ENABLE, 0x01);
    Sleep(1);

    return (I2cR32(DW_IC_STATUS) & 0x06) == 0x06;
}

I64 I2cInit()
{
    MemSet(&i2c, 0, sizeof(CI2c));
    i2c.d = I2cScan;

    if (IsKVM || !I2cSupported) {
        AdamLog("I2c Controller not found.\n");
        return 0;
    }
    i2c.mmio_base = PCIReadU32(I2C_PCI, 0x10) & 0xFFFFFFF0;

    // Enable MMIO, bus master
    U16 cmd = PCIReadU16(I2C_PCI, 0x04);
    cmd |= 0x0006;
    PCIWriteU16(I2C_PCI, 0x04, cmd);

    // Enable power
    U32 pmecs = PCIReadU32(I2C_PCI, 0x84);
    pmecs &= ~0x03;
    PCIWriteU32(I2C_PCI, 0x84, pmecs);

    if (!I2cInit1) {
        AdamLog("I2c peripheral init error.\n");
        return 0;
    }

    return 1;
}

U0 I2cCmd(...)
{
    I64 i;
    for (i = 0; i < argc; i++) {
        I2cW32(DW_IC_DATA_CMD, argv[i]);
    }
}

U0 I2cWakeDevice()
{
    I2cCmd(0x05, 0x00, 0x00, 0x08);
}

U0 I2cPoll()
{
    if (!i2c.ms) {
        return;
    }

    I2cCmd(0x00, 0x04);
    I64 len = 16;
    I64 i, v;

    for (i = 0; i < len; i++) {
        v = 0x0100;
        if (i == 0) {
            v |= 0x0400;
        }
        I2cCmd(v);
    }

    while (I2cR32(DW_IC_RXFLR) < len) { }
    for (i = 0; i < len; i++) {
        i2c.ms->report[i] = I2cR32(DW_IC_DATA_CMD) & 0xFF;
    }

    while (I2cR32(DW_IC_TXFLR) >= len - 4) { }
    I2cCmd(0x05, 0x00, 0x00, 0x00);
    while (I2cR32(DW_IC_TXFLR) > 0) { }
}

U0 I2cTask()
{
    CUefi* u = CORE0_32BIT_INIT;
    if (u->disable_i2c) {
        return;
    }

    if (!I2cInit) {
        return;
    }

    I2cWakeDevice;
    MsUpdate(GR_WIDTH / 2, GR_HEIGHT / 2, 0, 0, 0);
    PatchJmpRel32(&WinMsUpdate, &_I2cWinMsUpdate);
    ms_hard.installed = TRUE;
    ms.has_wheel = FALSE;

    while (1) {
        I2cPoll;
        Sleep(1);
    }
}
Spawn(&I2cTask, , "I\xfdC Task");
