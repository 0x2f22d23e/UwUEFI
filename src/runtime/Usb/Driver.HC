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

    usb.root = CALLOC_64(sizeof(CUsbHub));

    return XhciInit;
}
U0 UsbResetPorts()
{
    U32 p;
    for (p = 1; p <= usb.max_ports; p++) {
        XhciResetPort(p, 0);
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

Bool UsbDeviceIsHub(CUsbDevice* d)
{
    return d->desc.bDeviceClass == 0x09 || d->iface.bInterfaceClass == 0x09;
}

U0 UsbSetupDevice(CUsbDevice* d)
{
    if (UsbDeviceIsKeyboard(d)) {
        d->type = USB_TYPE_KEYBOARD;
        MemSet(usb.kb->report, 0, 8);
        PatchJmpRel32(&KbdMsHndlr, &_KbdMsHndlr);
        PatchJmpRel32(&KbdLEDsSet, &_KbdLEDsSet);
        keydev.ctrl_alt_in_irq_flags = 0;
        ms_hard.install_attempts++;
        ApplyWinKeyNavMenuPatch;
        usb.kb = d;
    }
    if (UsbDeviceIsMouse(d)) {
        d->type = USB_TYPE_MOUSE;
        MemSet(usb.ms->report, 0, 8);
        MsUpdate(GR_WIDTH / 2, GR_HEIGHT / 2, 0, 0, 0);
        PatchJmpRel32(&WinMsUpdate, &_UsbWinMsUpdate);
        ms_hard.installed = TRUE;
        ms.has_wheel = TRUE;
        usb.ms = d;
    }
    if (UsbDeviceIsHub(d)) {
        d->type = USB_TYPE_HUB;
        MemSet(d(CUsbHub*)->report, 0, 8);
        d(CUsbHub*)->enabled = TRUE;
    }
}

U0 UsbFreeDevice(CUsbDevice* d)
{
    if (!d) {
        return;
    }
    I64 i;
    switch (d->type) {
    case USB_TYPE_KEYBOARD:
        usb.kb = NULL;
        Free(d(CUsbKeyboard*)->kb.ring);
        Free(d(CUsbKeyboard*)->report);
        break;
    case USB_TYPE_MOUSE:
        usb.ms = NULL;
        Free(d(CUsbMouse*)->ms.ring);
        Free(d(CUsbMouse*)->report);
        break;
    case USB_TYPE_HUB:
        d(CUsbHub*)->enabled = FALSE;
        for (i = 0; i < HUB_MAX_PORTS; i++) {
            UsbFreeDevice(d(CUsbHub*)->dev[i]);
        }
        Free(d(CUsbHub*)->hub.ring);
        Free(d(CUsbHub*)->report);
        break;
    default:
        break;
    }
    Free(d->ep0.ring);
    Free(d->ctrl_buf);
    Free(d->dev_ctx_out);
    Free(d->input_ctx);
    Free(d);
}

U0 UsbScanRootPorts()
{
    U32 p;
    I64 state;
    CUsbDevice* res;
    CUsbHub* h = usb.root;
    for (p = 1; p <= usb.max_ports; p++) {
        state = XhciPortCcs(p, 0);
        if (h->ccs_state[p] != state) {
            if (state) {
                AdamLog("Root Usb Port %d connected.\n", p);
                res = XhciProbePort(p, 0);
                if (res) {
                    UsbSetupDevice(res);
                    h->dev[p] = res;
                }
            } else {
                AdamLog("Root Usb Port %d disconnected.\n", p);
                res = h->dev[p];
                h->dev[p] = NULL;
                UsbFreeDevice(res);
            }
        }
        h->ccs_state[p] = state;
    }
}

U0 UsbScanHubPorts(I64 i)
{
    CUsbHub* h = usb.root->dev[i];
    if (!h || !(h->type == USB_TYPE_HUB) || !h->enabled) {
        return;
    }
    U8* report = h->report;
    if (MemCmp(&h->last_report, report, 8)) {
        U32 p;
        I64 state;
        CUsbDevice* res;
        for (p = 1; p < h->hdesc.bNumPorts + 1; p++) {
            state = XhciPortCcs(p, h);
            if (h->ccs_state[p] != state) {
                if (state) {
                    AdamLog("Hub Usb Port %d connected.\n", p);
                    res = XhciProbePort(p, h);
                    if (res) {
                        UsbSetupDevice(res);
                        h->dev[p] = res;
                    }
                } else {
                    AdamLog("Hub Usb Port %d disconnected.\n", p);
                    res = h->dev[p];
                    h->dev[p] = NULL;
                    UsbFreeDevice(res);
                }
                XhciControlInZ(h, 0x23, 0x01, 0x0010, p);
            }
            h->ccs_state[p] = state;
        }
        MemSet(report, 0, 8);
    }
    MemCpy(&h->last_report, report, 8);
}

U0 UsbTask()
{
    if (!UsbInit) {
        return;
    }
    UsbResetPorts;
    I64 i;
    while (1) {
        UsbScanRootPorts;
        for (i = 1; i < HUB_MAX_PORTS; i++) {
            UsbScanHubPorts(i);
        }
        Sleep(10);
    }
}
Spawn(&UsbTask, , "Usb Task");

U0 UsbRep(CUsbHub* h = NULL, I64 depth = 1)
{
    if (!h) {
        "\dFD\dRoot Hub\n";
        h = usb.root;
    }

    I64 i;
    CUsbDevice* d;
    U8 pad[32];
    MemSet(pad, 0, 32);
    for (i = 0; i < (depth * 2); i++) {
        pad[i] = ' ';
    }

    for (i = 0; i < HUB_MAX_PORTS; i++) {
        if (d = h->dev[i]) {
            "%s\dFG,PURPLE\dPort #%02d\n", pad, i;
            "\dFD\d";
            "%s  Mfr: %s\n", pad, &d->mfr;
            "%s  Prd: %s\n", pad, &d->prod;
            "%s  Vnd: 0x%04x, Prd: 0x%04x\n", pad, d->desc.idVendor, d->desc.idProduct;
            "%s  Cls: 0x%02x, Sub: 0x%02x, Pro: 0x%02x\n",
                pad,
                d->iface.bInterfaceClass,
                d->iface.bInterfaceSubClass,
                d->iface.bInterfaceProtocol;
            if (d->iface.bInterfaceClass == 0x09) {
                "%s  Num Ports: %d\n", pad, d(CUsbHub*)->hdesc.bNumPorts;
                UsbRep(d, depth + 2);
            }
        }
    }
}
