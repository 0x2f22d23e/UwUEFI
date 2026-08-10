I64 UsbInit()
{
    MemSet(&usb, 0, sizeof(CUsb));
    usb.d = PCIClassFind(0x0c0330, 0);
    if (usb.d < 0) {
        AdamLog("Usb Controller not found.\n");
        return 0;
    }
    if (IsKVM) {
        PCIWriteU32(XHCI_PCI, 0x10, QEMU_XHCI_BAR0);
        PCIWriteU32(XHCI_PCI, 0x14, 0x0);
    }
    usb.mmio_base = PCIReadU32(XHCI_PCI, 0x10) & 0xFFFFFFF0;
    usb.cmd.ring = CALLOC_64(sizeof(CXhciTrb) * CMD_RING_TRBS);
    usb.cmd.q = 0;
    usb.cmd.cycle = 1;

    usb.evt.ring = CALLOC_64(sizeof(CXhciTrb) * CMD_RING_TRBS);
    usb.evt.q = 0;
    usb.evt.cycle = 1;

    usb.dcbaa = CALLOC_64(sizeof(U64) * (MAX_SLOTS_WANT + 1));
    usb.erst = CALLOC_64(sizeof(U64) * 2);

    usb.scratch_ptrs = CALLOC_64(sizeof(U64) * MAX_SCRATCHPAD);
    usb.scratch_buf = CALLOC_4K(MAX_SCRATCHPAD * 4096);

    return XhciInit;
}

U0 UsbResetPorts()
{
    U32 p;
    for (p = 1; p <= usb.max_ports; p++) {
        XhciResetPort(p);
    }
}

Bool UsbDeviceIsKeyboard(CUsbDevice* d)
{
    return d->iface.bInterfaceClass == 0x03 && d->iface.bInterfaceSubClass == 0x01 && d->iface.bInterfaceProtocol == 0x01;
}

Bool UsbDeviceIsMouse(CUsbDevice* d)
{
    return d->iface.bInterfaceClass == 0x03 && d->iface.bInterfaceSubClass == 0x01 && d->iface.bInterfaceProtocol == 0x02;
}

U0 UsbSetupDevice(CUsbDevice* d)
{
    if (UsbDeviceIsKeyboard(d)) {
        usb.kb = d;
        MemSet(usb.kb->report, 0, 8);
        PatchJmpRel32(&KbdMsHndlr, &_KbdMsHndlr);
        PatchJmpRel32(&KbdLEDsSet, &_KbdLEDsSet);
        keydev.ctrl_alt_in_irq_flags = 0;
        ms_hard.install_attempts++;
        ApplyWinKeyNavMenuPatch;
    }
    if (UsbDeviceIsMouse(d)) {
        usb.ms = d;
        MemSet(usb.ms->report, 0, 8);
        MsUpdate(GR_WIDTH / 2, GR_HEIGHT / 2, 0, 0, 0);
        PatchJmpRel32(&WinMsUpdate, &_WinMsUpdate);
        ms_hard.installed = TRUE;
        ms.has_wheel = TRUE;
    }
}

U0 UsbScanPorts()
{
    U32 p;
    I64 state;
    CUsbDevice* res;
    for (p = 1; p <= usb.max_ports; p++) {
        state = XhciPortCcs(p);
        if (usb.ccs_state[p] != state) {
            if (state) {
                AdamLog("Usb Port %d connected.\n", p);
                res = XhciProbePort(p);
                if (res) {
                    UsbSetupDevice(res);
                    usb.dev[p] = res;
                }
            } else {
                AdamLog("Usb Port %d disconnected.\n", p);
                usb.dev[p] = NULL;
            }
        }
        usb.ccs_state[p] = state;
    }
}

U0 UsbTask()
{
    if (!UsbInit) {
        return;
    }
    UsbResetPorts;
    while (1) {
        UsbScanPorts;
        Sleep(10);
    }
}
Spawn(&UsbTask, , "Usb Task");

U0 UsbRep()
{
    CUsbDevice* d;
    I64 i;
    for (i = 0; i < 32; i++) {
        if (d = usb.dev[i]) {
            "\dFG,PURPLE\dPort #%02d\n", i;
            "\dFD\d";
            "  Mfr:    %s\n", &d->mfr;
            "  Prod:   %s\n", &d->prod;
            "  Vendor: 0x%04x, Prod: 0x%04x\n", d->desc.idVendor, d->desc.idProduct;
            "  Class:  %02d, Sub: %02d, Proto: %02d\n",
                d->iface.bInterfaceClass,
                d->iface.bInterfaceSubClass,
                d->iface.bInterfaceProtocol;
        }
    }
}
