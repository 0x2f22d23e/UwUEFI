U0 XhciDebug(U8* fmt, ...)
{
    if (usb.debug) {
        U8* buf = StrPrintJoin(NULL, fmt, argc, argv);
        AdamLog(buf);
        Free(buf);
    }
}

U0 XhciDoorbell(U32 slot_id, U32 target)
{
    asm {
        // M'fence *tips cache*
        DU32 0x90f0ae0f;
    }
    MMIO_WRITE_U32(usb.db_base + (slot_id * 4), target);
}

I32 XhciWaitEvent(U32 expect_type, CXhciTrb* out_evt, U32 timeout_iters)
{
    U32 i, type;
    for (i = 0; i < timeout_iters; i++) {
        CXhciTrb* e = &usb.evt.ring[usb.evt.q];
        if ((e->d3 & 1) == usb.evt.cycle) {
            CXhciTrb got;
            MemCpy(&got, e, sizeof(CXhciTrb));
            usb.evt.q++;
            if (usb.evt.q == EVT_RING_TRBS) {
                usb.evt.q = 0;
                usb.evt.cycle ^= 1;
            }

            MMIO_WRITE_U64(usb.rt_base + RT_IR0_ERDP, &usb.evt.ring[usb.evt.q] | 8);
            type = (got.d3 >> 10) & 0x3f;
            if (type == expect_type) {
                MemCpy(out_evt, &got, sizeof(CXhciTrb));
                return 1;
            }
        }
    }
    return 0;
}

U64 XhciCmdEnqueue(U32 d0, U32 d1, U32 d2, U32 d3_no_cycle)
{
    CXhciTrb* slot = &usb.cmd.ring[usb.cmd.q];
    U64 phys = slot;
    slot->d0 = d0;
    slot->d1 = d1;
    slot->d2 = d2;
    slot->d3 = d3_no_cycle | usb.cmd.cycle;
    U32 next = usb.cmd.q + 1;
    if (next == (CMD_RING_TRBS - 1) & U32_MAX) {
        usb.cmd.ring[CMD_RING_TRBS - 1].d3 = (6 << 10) | (1 << 1) | usb.cmd.cycle;
        usb.cmd.q = 0;
        usb.cmd.cycle ^= 1;
    } else
        usb.cmd.q = next;
    return phys;
}

U0 XhciEp0Enqueue(CUsbDevice* d, U32 d0, U32 d1, U32 d2, U32 d3_no_cycle)
{
    CXhciTrb* slot = &d->ep0.ring[d->ep0.q];
    slot->d0 = d0;
    slot->d1 = d1;
    slot->d2 = d2;
    slot->d3 = d3_no_cycle | d->ep0.cycle;
    U32 next = d->ep0.q + 1;
    if (next == (EPx_RING_TRBS - 1)) {
        CXhciTrb* link = &d->ep0.ring[EPx_RING_TRBS - 1];
        link->d3 = (6 << 10) | (1 << 1) | d->ep0.cycle;
        d->ep0.q = 0;
        d->ep0.cycle ^= 1;
    } else {
        d->ep0.q = next;
    }
}

U32 XhciControlIn(CUsbDevice* d, U32 bm_request_type, U32 b_request, U32 w_value, U32 w_index, U32 want_len)
{
    if (want_len > 256) {
        want_len = 256;
    }

    U32 slot_id = d->slot_id;
    U64 buf_phys = d->ctrl_buf;
    MemSet(buf_phys, 0, want_len);

    XhciEp0Enqueue(d, bm_request_type | (b_request << 8) | (w_value << 16), w_index | (want_len << 16), 8, (2 << 10) | (1 << 6) | (3 << 16));
    XhciEp0Enqueue(d, buf_phys.u32[0], buf_phys.u32[1], want_len, (3 << 10) | (1 << 16));
    XhciEp0Enqueue(d, 0, 0, 0, (4 << 10) | (1 << 5));
    XhciDoorbell(slot_id, 1);

    CXhciTrb evt;
    if (!XhciWaitEvent(32, &evt, XHCI_WAIT_INTERVAL)) {
        return 0xff;
    }
    return (evt.d2 >> 24) & 0xff;
}

U32 XhciControlInZ(CUsbDevice* d, U32 bm_request_type, U32 b_request, U32 w_value, U32 w_index)
{
    U32 slot_id = d->slot_id;
    U32 trt_field = (1 << 6);

    XhciEp0Enqueue(d, bm_request_type | (b_request << 8) | (w_value << 16), w_index, 8, (2 << 10) | trt_field);
    XhciEp0Enqueue(d, 0, 0, 0, (4 << 10) | (1 << 5) | (1 << 16)); // Kept completely original to prevent OS crashes!
    XhciDoorbell(slot_id, 1);

    CXhciTrb evt;
    if (!XhciWaitEvent(32, &evt, XHCI_WAIT_INTERVAL)) {
        return 0xff;
    }
    return (evt.d2 >> 24) & 0xff;
}

U0 XhciBiosHandoff(U32 hccparams1)
{
    U32 xecp = (hccparams1 >> 16) & 0xFFFF;
    if (xecp == 0) {
        return;
    }
    U64 addr = usb.mmio_base + (xecp * 4);
    I32 i;

    while (1) {
        U32 cap = MMIO_READ_U32(addr);
        I32 id = cap & 0xFF;
        I32 next = (cap >> 8) & 0xFF;

        if (id == 1) {
            cap |= (1 << 24);
            MMIO_WRITE_U32(addr, cap);
            for (i = 0; i < 1000000; i++) {
                cap = MMIO_READ_U32(addr);
                if (!(cap & (1 << 16)) && (cap & (1 << 24))) {
                    break;
                }
            }
            return;
        }
        if (next == 0) {
            return;
        }

        addr = addr + (next * 4);
    }
}

U0 XhciDrainPendingEvents()
{
    U32 guard;
    for (guard = 0; guard < EVT_RING_TRBS + 4; guard++) {
        CXhciTrb* e = &usb.evt.ring[usb.evt.q];
        if ((e->d3 & 1) != usb.evt.cycle) {
            break;
        }
        usb.evt.q++;
        if (usb.evt.q == EVT_RING_TRBS) {
            usb.evt.q = 0;
            usb.evt.cycle ^= 1;
        }

        /* ERDP bit 3 clears EHB and must be written as one. */
        MMIO_WRITE_U64(usb.rt_base + RT_IR0_ERDP, (&usb.evt.ring[usb.evt.q]) | 8);
    }
}

U32 XhciRootPortSc(I32 p)
{
    U64 addr = usb.op_base + OP_PORTSC_BASE + ((p - 1) * 0x10);
    return MMIO_READ_U32(addr);
}

U32 XhciHubPortSc(I32 p, CUsbHub* h)
{
    if (!h) {
        return 0;
    }

    U32 cc = XhciControlIn(h, 0xA3, 0x00, 0x0000, p, 4);
    if (cc != 1) {
        return 0;
    }

    U8* buf = h->ctrl_buf;
    U16 status = buf[0] | (buf[1] << 8);
    U16 change = buf[2] | (buf[3] << 8);
    U32 sc = 0;

    if (status & 0x0001) {
        sc |= (1 << 0);
    }
    if (status & 0x0002) {
        sc |= (1 << 1);
    }
    if (status & 0x0010) {
        sc |= (1 << 4);
    }

    U32 speed_id = 1;
    if (status & 0x0200) {
        speed_id = 2;
    } else if (status & 0x0400) {
        speed_id = 3;
    }

    sc |= (speed_id << 10);

    if (change & 0x0001) {
        sc |= (1 << 17);
    }
    if (change & 0x0002) {
        sc |= (1 << 18);
    }
    if (change & 0x0010) {
        sc |= (1 << 21);
    }

    return sc;
}

U32 XhciPortSc(I32 p, CUsbHub* h)
{
    if (!h) {
        return XhciRootPortSc(p);
    }
    return XhciHubPortSc(p, h);
}

Bool XhciPortCcs(I32 p, CUsbHub* h)
{
    return XhciPortSc(p, h) & PORTSC_CCS;
}

I32 XhciResetRootPort(I32 p)
{
    U64 addr = usb.op_base + OP_PORTSC_BASE + ((p - 1) * 0x10);
    U32 portsc = MMIO_READ_U32(addr);
    U32 pls = (portsc >> 5) & 0xF;
    if (pls == 0) {
        return (portsc & PORTSC_CCS) != 0;
    }

    U32 i;
    MMIO_WRITE_U32(addr, (portsc & PORTSC_PP) | (1 << 4));
    for (i = 0; i < 100; i++) {
        portsc = MMIO_READ_U32(addr);
        if (portsc & (1 << 21)) {
            break;
        }
        Sleep(1);
    }

    MMIO_WRITE_U32(addr, (portsc & PORTSC_PP) | (1 << 21) | (1 << 17));
    portsc = MMIO_READ_U32(addr);
    return (portsc & PORTSC_CCS) && (portsc & (1 << 1));
}

I32 XhciResetHubPort(I32 p, CUsbHub* h)
{
    if (!h || !XhciPortCcs(p, h)) {
        return 0;
    }

    U32 cc = XhciControlInZ(h, 0x23, 0x03, 0x0004, p);
    if (cc != 1) {
        return 0;
    }

    I64 i;
    U32 portsc;
    for (i = 0; i < 100; i++) {
        portsc = XhciHubPortSc(p, h);
        if (portsc & (1 << 21)) {
            break;
        }
        Sleep(1);
    }

    XhciControlInZ(h, 0x23, 0x01, 0x0014, p);

    portsc = XhciHubPortSc(p, h);
    return (portsc & PORTSC_CCS) && (portsc & (1 << 1));
}

I32 XhciResetPort(I32 p, CUsbHub* h)
{
    if (!h) {
        return XhciResetRootPort(p);
    }
    return XhciResetHubPort(p, h);
}

U32 XhciGetDeviceDescriptor(CUsbDevice* d, U32 want_len)
{
    return XhciControlIn(d, 0x80, 6, 0x0100, 0, want_len);
}

U32 XhciGetStringDescriptor(CUsbDevice* d, U16 index, U32 want_len)
{
    return XhciControlIn(d, 0x80, 6, 0x0300 | (index & 0xff), d->lang_id, want_len);
}

U0 XhciGetWideString(CUsbDevice* d, U8* buf)
{
    MemSet(buf, 0, USB_STR);
    I64 total = d->ctrl_buf[0];
    if (!total) {
        return;
    }
    I64 ch;
    I64 n = 0;
    while (total) {
        n += 2;
        total -= 2;
        ch = d->ctrl_buf[n];
        if (ch >= ' ') {
            *buf++ = ch;
        }
    }
    *buf = 0;
}

Bool XhciFetchInterfaceDescriptor(CUsbDevice* d)
{
    U32 cc = XhciControlIn(d, 0x80, 6, 0x0200, 0, 9);
    if (cc != 1 && cc != 13) {
        return 0;
    }
    U32 total = d->ctrl_buf[2] | (d->ctrl_buf[3] << 8);
    if (total < 9) {
        return 0;
    }
    total = MinI64(total, 256);
    cc = XhciControlIn(d, 0x80, 6, 0x0200, 0, total);
    if (cc != 1 && cc != 13) {
        return 0;
    }

    MemCpy(&d->iface, d->ctrl_buf + 9, sizeof(CUsbInterfaceDesc));
    return 1;
}

U0 XhciNewDevice(CUsbDevice* d, U32 p, U32 slot_id)
{
    MemSet(d, 0, sizeof(CUsbDevice));
    d->port = p;
    d->slot_id = slot_id;
    d->input_ctx = CALLOC_64(32 * 32);
    d->dev_ctx_out = CALLOC_64(32 * 32);
    d->ctrl_buf = CALLOC_4K(256);

    d->ep0.ring = CALLOC_64(sizeof(CXhciTrb) * EPx_RING_TRBS);
    U64 ring_addr = &d->ep0.ring[0];
    CXhciTrb* link = &d->ep0.ring[EPx_RING_TRBS - 1];
    link->d0 = ring_addr;
    link->d1 = (ring_addr >> 32);
    link->d2 = 0;
    link->d3 = (6 << 10) | (1 << 1) | 1;
    d->ep0.q = 0;
    d->ep0.cycle = 1;
}

I32 XhciEvaluateEp0MaxPacket(CUsbDevice* d, U32 new_max_packet)
{
    U32 slot_id = d->slot_id;
    MemSet(d->input_ctx, 0, 32 * 32);
    U32* ic = d->input_ctx;
    ic[1] = (1 << 1);
    U32* ep0_ctx = (d->input_ctx(U64) + (usb.context_size * 2));
    ep0_ctx[1] = (3 << 1) | (4 << 3) | (new_max_packet << 16);

    U64 input_ctx_phys = d->input_ctx;
    XhciCmdEnqueue(input_ctx_phys.u32[0], input_ctx_phys.u32[1], 0, (13 << 10) | (slot_id << 24));
    XhciDoorbell(0, 0);
    CXhciTrb evt;
    if (!XhciWaitEvent(33, &evt, XHCI_WAIT_INTERVAL)) {
        return 0;
    }
    return ((evt.d2 >> 24) & 0xff) == 1;
}

U0 XhciRingInit(CXhciRing* r, I64 size)
{
    r->ring = CALLOC_64K(sizeof(CXhciTrb) * size);
    MemSet(r->ring, 0, size * sizeof(CXhciTrb));
    U64 addr = r->ring;
    CXhciTrb* link = &r->ring[size - 1];
    link->d0 = addr;
    link->d1 = (addr >> 32);
    link->d2 = 0;
    link->d3 = (6 << 10) | (1 << 1) | 1;
    *r->q = 0;
    *r->cycle = 1;
}

U0 XhciIntInRingSetup(CXhciRing* r, U8* buf, I64 data_size)
{
    I64 i;
    U32* int_in_ring = r->ring;
    U32 max_data_slots = EPx_RING_TRBS - 1;
    MemSet(r->ring, 0, max_data_slots * 16);

    U64 data_phys_base = buf;
    U64 ring_phys_base = r->ring;
    for (i = 0; i < max_data_slots; i++) {
        U32 offset = i * 4;
        int_in_ring[offset + 0] = data_phys_base.u32[0];
        int_in_ring[offset + 1] = data_phys_base.u32[1];
        int_in_ring[offset + 2] = data_size;
        int_in_ring[offset + 3] = (1 << 10) | 1;
    }

    U32 link_offset = max_data_slots * 4;
    int_in_ring[link_offset + 0] = ring_phys_base.u32[0];
    int_in_ring[link_offset + 1] = ring_phys_base.u32[1];
    int_in_ring[link_offset + 2] = 0;
    int_in_ring[link_offset + 3] = (6 << 10) | 1;
}

CUsbKeyboard* XhciConfigKeyboard(CUsbDevice* d)
{
    CUsbKeyboard* k = CALLOC_64(sizeof(CUsbKeyboard));
    MemCpy(k, d, sizeof(CUsbDevice));

    XhciRingInit(&k->kb, EPx_RING_TRBS);
    k->report = CALLOC_64K(16);

    MemSet(k->input_ctx, 0, (32 * 32));

    U8* ctx_base = k->input_ctx;
    U32* ic = ctx_base;

    U32 in_dci = 3;
    ic[1] = (1 << 0) | (1 << in_dci);

    U32* slot_in = (ctx_base(U64) + usb.context_size);
    U32* slot_out = k->dev_ctx_out;
    I64 i, j;
    for (j = 0; j < 8; j++) {
        slot_in[j] = slot_out[j];
    }

    slot_in[3] = 0;
    slot_in[0] = (slot_in[0] & ~(0x1F << 27)) | (in_dci << 27);

    U32* ep_in = (ctx_base(U64) + (usb.context_size * (in_dci + 1)));
    U64 in_ring_phys = k->kb.ring;
    ep_in[0] = (7 << 16);
    ep_in[1] = (8 << 16) | (7 << 3) | (3 << 1);
    ep_in[2] = in_ring_phys.u32[0] | 1;
    ep_in[3] = in_ring_phys.u32[1];
    ep_in[4] = 8;

    U64 input_ctx_phys = k->input_ctx;
    XhciCmdEnqueue(input_ctx_phys.u32[0], input_ctx_phys.u32[1], 0, (12 << 10) | (k->slot_id << 24));
    XhciDoorbell(0, 0);

    CXhciTrb evt;
    if (!XhciWaitEvent(33, &evt, XHCI_WAIT_INTERVAL)) {
        XhciDebug("XhciConfigKeyboard: ERR 0001\n");
        return 0;
    }
    if (((evt.d2 >> 24) & 0xff) != 1) {
        XhciDebug("XhciConfigKeyboard: ERR 0002\n");
        return 0;
    }

    XhciControlInZ(k, 0x00, 9, 1, 0);
    XhciControlInZ(k, 0x21, 0x0B, 0x0000, 0x0000);
    XhciControlInZ(k, 0x21, 0x0A, 0x0000, 0x0000);

    XhciIntInRingSetup(&k->kb, k->report, 8);
    XhciDoorbell(k->slot_id, 3);

    return k;
}

CUsbMouse* XhciConfigMouse(CUsbDevice* d)
{
    CUsbMouse* m = CALLOC_64(sizeof(CUsbMouse));
    MemCpy(m, d, sizeof(CUsbDevice));

    XhciRingInit(&m->ms, EPx_RING_TRBS);
    m->report = CALLOC_64K(16);

    MemSet(m->input_ctx, 0, (32 * 32));

    U8* ctx_base = m->input_ctx;
    U32* ic = ctx_base;

    U32 in_dci = 3;
    ic[1] = (1 << 0) | (1 << in_dci);

    U32* slot_in = (ctx_base(U64) + usb.context_size);
    U32* slot_out = m->dev_ctx_out;
    I64 i, j;
    for (j = 0; j < 8; j++) {
        slot_in[j] = slot_out[j];
    }

    slot_in[3] = 0;
    slot_in[0] = (slot_in[0] & ~(0x1F << 27)) | (in_dci << 27);

    U32* ep_in = (ctx_base(U64) + (usb.context_size * (in_dci + 1)));
    U64 in_ring_phys = m->ms.ring;
    ep_in[0] = (7 << 16);
    ep_in[1] = (8 << 16) | (7 << 3) | (3 << 1);
    ep_in[2] = in_ring_phys.u32[0] | 1;
    ep_in[3] = in_ring_phys.u32[1];
    ep_in[4] = 8;

    U64 input_ctx_phys = m->input_ctx;
    XhciCmdEnqueue(input_ctx_phys.u32[0], input_ctx_phys.u32[1], 0, (12 << 10) | (m->slot_id << 24));
    XhciDoorbell(0, 0);

    CXhciTrb evt;
    if (!XhciWaitEvent(33, &evt, XHCI_WAIT_INTERVAL)) {
        XhciDebug("XhciConfigMouse: ERR 0001\n");
        return 0;
    }
    if (((evt.d2 >> 24) & 0xff) != 1) {
        XhciDebug("XhciConfigMouse: ERR 0002\n");
        return 0;
    }

    XhciControlInZ(m, 0x00, 9, 1, 0);
    XhciControlInZ(m, 0x21, 0x0B, 0x0000, 0x0000);
    XhciControlInZ(m, 0x21, 0x0A, 0x0000, 0x0000);

    XhciIntInRingSetup(&m->ms, m->report, 8);
    XhciDoorbell(m->slot_id, 3);

    return m;
}

I64 XhciSetHubPortsPower(CUsbHub* h)
{
    I64 i;
    U32 cc;
    for (i = 0; i < h->hdesc.bNumPorts; i++) {
        cc = XhciControlInZ(h, 0x23, 0x03, 0x0008, i + 1);
        if (cc != 1) {
            XhciDebug("XhciSetHubPortsPower: ERR port %d code %d\n", i + 1, cc);
            return 0;
        }
        Sleep(20);
    }
    return 1;
}

U32 XhciGetHubDescriptor(CUsbHub* h)
{
    return XhciControlIn(h, 0xa0, 6, 0x2900, 0, 9);
}

CUsbHub* XhciConfigHub(CUsbDevice* d)
{
    CUsbHub* h = CALLOC_64(sizeof(CUsbHub));
    MemCpy(h, d, sizeof(CUsbDevice));

    // Get Hub Descriptor
    U32 cc = XhciGetHubDescriptor(h);
    if (cc != 1 && cc != 13) {
        return 0;
    }
    MemCpy(&h->hdesc, h->ctrl_buf, 9);

    XhciRingInit(&h->hub, EPx_RING_TRBS);
    h->report = CALLOC_64K(16);

    I64 i;
    CXhciTrb evt;

    if (IsKVM) {
        XhciSetHubPortsPower(h);
    }

    U8* ctx_base = h->input_ctx;
    U32* ic = ctx_base;

    U32 in_dci = 3;
    ic[1] = (1 << 0) | (1 << in_dci);

    U32* slot_in = (ctx_base(U64) + usb.context_size);
    U32* slot_out = h->dev_ctx_out;
    I64 j;
    for (j = 0; j < 8; j++) {
        slot_in[j] = slot_out[j];
    }

    slot_in[0] = (slot_in[0] & ~(0x1F << 27)) | (in_dci << 27) | (1 << 26);
    slot_in[1] = (slot_in[1] & 0x0000FFFF) | (h->port << 16) | (h->hdesc.bNumPorts << 24);
    slot_in[2] = SLOT_2_TT_TIME(HUB_TTT_GET(h->hdesc.wHubCharacteristics));

    U64 input_ctx_phys = h->input_ctx;

    if (!IsKVM) {
        XhciCmdEnqueue(input_ctx_phys.u32[0], input_ctx_phys.u32[1], 0, (11 << 10) | (h->slot_id << 24));
        XhciDoorbell(0, 0);
        if (!XhciWaitEvent(33, &evt, XHCI_WAIT_INTERVAL)) {
            XhciDebug("XhciConfigHub: ERR 0001\n");
            return 0;
        }
    }

    U32* ep_in = (ctx_base(U64) + (usb.context_size * (in_dci + 1)));
    U64 in_ring_phys = h->hub.ring;
    if (IsKVM) {
        ep_in[0] = (7 << 16);
        ep_in[1] = (8 << 16) | (7 << 3) | (3 << 1);
        ep_in[4] = 8;
    } else {
        ep_in[0] = (12 << 16);
        ep_in[1] = (1 << 16) | (3 << 3) | (3 << 1);
        ep_in[4] = 1 | (1 << 16);
    }
    ep_in[2] = in_ring_phys.u32[0] | 1;
    ep_in[3] = in_ring_phys.u32[1];

    XhciCmdEnqueue(input_ctx_phys.u32[0], input_ctx_phys.u32[1], 0, (12 << 10) | (h->slot_id << 24));
    XhciDoorbell(0, 0);

    if (!XhciWaitEvent(33, &evt, XHCI_WAIT_INTERVAL)) {
        XhciDebug("XhciConfigHub: ERR 0002\n");
        return 0;
    }
    if (((evt.d2 >> 24) & 0xff) != 1) {
        XhciDebug("XhciConfigHub: ERR 0003\n");
        return 0;
    }

    cc = XhciControlInZ(h, 0x00, 0x09, 1, 0);
    if (cc != 1) {
        XhciDebug("XhciConfigHub: ERR 0004\n");
        return 0;
    }

    XhciIntInRingSetup(&h->hub, h->report, 8);
    XhciDoorbell(h->slot_id, 3);
    Sleep(20);

    if (!IsKVM) {
        XhciSetHubPortsPower(h);
    }

    return h;
}

CUsbDevice* XhciConfigGeneric(CUsbDevice* d)
{
    CUsbDevice* g = CALLOC_64(sizeof(CUsbDevice));
    MemCpy(g, d, sizeof(CUsbDevice));
    return g;
}

CUsbDevice* XhciProbePort(I32 p, CUsbHub* h)
{
    U32 portsc, pls, speed_id, max_packet;
    U32 cc, slot_id;
    CXhciTrb evt;

    portsc = XhciPortSc(p, h);
    if (!(portsc & PORTSC_CCS)) {
        XhciDebug("XhciProbePort: ERR 0001, port %d portsc 0x%08x\n", p, portsc);
        return 0;
    }
    pls = (portsc >> 5) & 0x0f;
    if (pls != 0) {
        if (!XhciResetPort(p, h)) {
            XhciDebug("XhciProbePort: ERR 0002, port %d\n", p);
            return 0;
        }
    }
    portsc = XhciPortSc(p, h);
    if (!(portsc & PORTSC_CCS)) {
        XhciDebug("XhciProbePort: ERR 0003, port %d portsc 0x%08x\n", p, portsc);
        return 0;
    }

    if (h) {
        I32 need_reset = 0;
        if (!h) {
            pls = (portsc >> 5) & 0x0f;
            if (pls != 0) {
                need_reset = 1;
            }
        } else {
            // If it's a hub port and bit 1 (Port Enabled) is 0, we MUST reset it!
            if (!(portsc & (1 << 1))) {
                need_reset = 1;
            }
        }

        if (need_reset) {
            if (!XhciResetPort(p, h)) {
                return 0;
            }
        }
    }

    XhciDrainPendingEvents;

    speed_id = (portsc >> 10) & 0x0f;
    max_packet = 512;
    if (speed_id == 1 || speed_id == 2) {
        max_packet = 8;
    } else if (speed_id == 3) {
        max_packet = 64;
    }
    XhciDebug("XhciProbePort: INFO port %d speed_id %d max_packet %d\n", p, speed_id, max_packet);

    XhciCmdEnqueue(0, 0, 0, (9 << 10));
    XhciDoorbell(0, 0);

    if (!XhciWaitEvent(33, &evt, XHCI_WAIT_INTERVAL)) {
        XhciDebug("XhciProbePort: ERR 0004, port %d\n", p);
        return 0;
    }

    cc = (evt.d2 >> 24) & 0xff;
    slot_id = (evt.d3 >> 24) & 0xff;

    if (cc != 1 || slot_id == 0 || slot_id > MAX_SLOTS_WANT) {
        XhciDebug("XhciProbePort: ERR 0005, port %d, slot_id: %d, cc: %d\n", p, slot_id, cc);
        return 0;
    }

    XhciDebug("XhciProbePort: INFO port %d slot_id %d\n", p, slot_id);

    CUsbDevice d;
    XhciNewDevice(&d, p, slot_id);

    U32* ic = d.input_ctx;
    ic[1] = (1 << 0) | (1 << 1);

    U32* slot_ctx = (d.input_ctx(U64) + usb.context_size);

    if (!h) {
        slot_ctx[0] = (speed_id << 20) | (1 << 27);
        slot_ctx[1] = (p << 16);
        slot_ctx[2] = 0;
        slot_ctx[3] = 0;
    } else {
        slot_ctx[0] = (speed_id << 20) | (1 << 27) | p;
        slot_ctx[1] = (h->port << 16);
        slot_ctx[2] = h->slot_id | ((p & 0xff) << 8);
        slot_ctx[3] = 0;
    }

    U64 ep0_ring_phys = &d.ep0.ring[0];
    U32* ep0_ctx = (d.input_ctx(U64) + (usb.context_size * 2));
    ep0_ctx[1] = (3 << 1) | (4 << 3) | (max_packet << 16);
    ep0_ctx[2] = ep0_ring_phys.u32[0] | 1;
    ep0_ctx[3] = ep0_ring_phys.u32[1];
    ep0_ctx[4] = 8 | (max_packet << 16);

    usb.dcbaa[slot_id] = d.dev_ctx_out;

    U64 input_ctx_phys = d.input_ctx;
    XhciCmdEnqueue(input_ctx_phys.u32[0], input_ctx_phys.u32[1], 0, (11 << 10) | (slot_id << 24));
    XhciDoorbell(0, 0);

    I32 addr_ok = 0;
    I32 attempt;
    for (attempt = 0; attempt < 3 && !addr_ok; attempt++) {
        if (attempt > 0) {
            XhciCmdEnqueue(input_ctx_phys.u32[0], input_ctx_phys.u32[1], 0, (11 << 10) | (slot_id << 24));
            XhciDoorbell(0, 0);
        }
        if (!XhciWaitEvent(33, &evt, XHCI_WAIT_INTERVAL)) {
            goto probe_next_a;
        }
        cc = (evt.d2 >> 24) & 0xff;
        if (cc != 1) {
            XhciDebug("XhciProbePort: Address Device failed: attempt %d port %d parent_slot %d: code %d\n", attempt + 1, p, h->slot_id, cc);
            goto probe_next_a;
        }
        addr_ok = 1;
    probe_next_a:
    }
    if (!addr_ok) {
        XhciDebug("XhciProbePort: TRB RAW: d0:0x%08X | d1:0x%08X | d2:0x%08X | d3:0x%08X\n",
            evt.d0, evt.d1, evt.d2, evt.d3);
        XhciDebug("XhciProbePort: ERR 0006, port %d\n", p);
        return 0;
    }

    if (speed_id == 1) {
        cc = XhciGetDeviceDescriptor(&d, 8);
        if (cc == 1 || cc == 13) {
            U32 real_mp = d.ctrl_buf[7];
            if (real_mp != 0 && real_mp != max_packet) {
                if (XhciEvaluateEp0MaxPacket(&d, real_mp)) {
                    max_packet = real_mp;
                }
            }
        }
    }

    cc = XhciGetDeviceDescriptor(&d, 18);
    if (cc == 0xff) {
        XhciDebug("XhciProbePort: ERR 0007, port %d\n", p);
        return 0;
    }
    if (cc != 1 && cc != 13) {
        XhciDebug("XhciProbePort: ERR 0008, port %d\n", p);
        return 0;
    }

    MemCpy(&d.desc, d.ctrl_buf, sizeof(CUsbDeviceDesc));
    XhciDebug("XhciProbePort: INFO port %d vendor 0x%04x device 0x%04x\n", p, d.desc.idVendor, d.desc.idProduct);

    cc = XhciGetStringDescriptor(&d, 0, 256);
    if (cc == 1) {
        d.lang_id = (d.ctrl_buf[3] << 8) | d.ctrl_buf[2];
        cc = XhciGetStringDescriptor(&d, d.desc.iManufacturer, 256);
        if (cc == 1) {
            XhciGetWideString(&d, &d.mfr);
        } else {
            StrCpy(&d.mfr, "");
        }
        cc = XhciGetStringDescriptor(&d, d.desc.iProduct, 256);
        if (cc == 1) {
            XhciGetWideString(&d, &d.prod);
        } else {
            StrCpy(&d.prod, "");
        }
        XhciDebug("XhciProbePort: INFO port %d %s %s\n", p, d.mfr, d.prod);
    } else {
        XhciDebug("XhciProbePort: ERR 0009, port %d\n", p);
    }

    cc = XhciFetchInterfaceDescriptor(&d);
    if (cc == 1) {
        XhciDebug("XhciProbePort: INFO port %d class %d subclass %d protocol %d\n", p, d.iface.bInterfaceClass, d.iface.bInterfaceSubClass, d.iface.bInterfaceProtocol);

        if (d.desc.bDeviceClass == 0x09 || d.iface.bInterfaceClass == 0x09) {
            return XhciConfigHub(&d);
        }
        if (d.iface.bInterfaceClass == 0x03 && d.iface.bInterfaceSubClass == 0x01) {
            switch (d.iface.bInterfaceProtocol) {
            case 0x01:
                return XhciConfigKeyboard(&d);
            case 0x02:
                return XhciConfigMouse(&d);
            default:
                break;
            }
        }
        return XhciConfigGeneric(&d);
    } else {
        XhciDebug("XhciProbePort: ERR 0010, port %d\n", p);
    }

    return 0;
}

U32 XhciSsPortMask(U32 hccparams1)
{
    U32 mask = 0;
    U32 xecp = (hccparams1 >> 16) & 0xFFFF;
    if (xecp == 0) {
        return 0;
    }
    U64 addr = usb.mmio_base + (xecp * 4);
    I32 i;
    while (1) {
        U32 cap = MMIO_READ_U32(addr);
        I32 id = cap & 0xFF;
        I32 next = (cap >> 8) & 0xFF;
        if (id == 2) {
            U32 dw2 = MMIO_READ_U32(addr + 8);
            I32 major = (cap >> 24) & 0xFF;
            I32 off = dw2 & 0xFF;
            I32 cnt = (dw2 >> 8) & 0xFF;
            if (major >= 3) {
                for (i = 0; i < cnt; i++) {
                    I32 pn = off + i;
                    if (pn >= 1 && pn <= 32) {
                        mask |= (1 << (pn - 1));
                    }
                }
            }
        }
        if (next == 0) {
            break;
        }
        addr = addr + (next * 4);
    }
    return mask;
}

I32 XhciInit()
{
    U64 mmio_base = usb.mmio_base;
    XhciDebug("Test debug line\n");

    I32 caplen = MMIO_READ_U32(mmio_base + CAP_CAPLENGTH) & 0xff;
    U32 hcsparams1 = MMIO_READ_U32(mmio_base + CAP_HCSPARAMS1);
    U32 hcsparams2 = MMIO_READ_U32(mmio_base + CAP_HCSPARAMS2);
    U32 hccparams1 = MMIO_READ_U32(mmio_base + CAP_HCCPARAMS1);
    U32 dboff = MMIO_READ_U32(mmio_base + CAP_DBOFF) & ~0x3;
    U32 rtsoff = MMIO_READ_U32(mmio_base + CAP_RTSOFF) & ~0x1F;

    U64 op_base = mmio_base + caplen;
    U64 rt_base = mmio_base + rtsoff;
    U64 db_base = mmio_base + dboff;

    usb.op_base = op_base;
    usb.rt_base = rt_base;
    usb.db_base = db_base;
    usb.max_slots = hcsparams1 & 0xFF;
    usb.max_intrs = (hcsparams1 >> 8) & 0x7FF;
    usb.max_ports = (hcsparams1 >> 24) & 0xFF;
    if (hccparams1 & (1 << 2)) {
        usb.context_size = 64;
    } else {
        usb.context_size = 32;
    }

    XhciBiosHandoff(hccparams1);
    U32 i, p, c, s, portsc;
    U64 addr;

    U32 cmd = MMIO_READ_U32(op_base + OP_USBCMD);
    if (cmd & USBCMD_RUN) {
        MMIO_WRITE_U32(op_base + OP_USBCMD, cmd & ~USBCMD_RUN);
        for (i = 0; i < 2000000; i++)
            if (MMIO_READ_U32(op_base + OP_USBSTS) & USBSTS_HCH) {
                break;
            }
    }

    MMIO_WRITE_U32(op_base + OP_USBCMD, USBCMD_HCRST);
    for (i = 0; i < 4000000; i++) {
        c = MMIO_READ_U32(op_base + OP_USBCMD);
        s = MMIO_READ_U32(op_base + OP_USBSTS);
        if (!(c & USBCMD_HCRST) && !(s & USBSTS_CNR)) {
            break;
        }
    }

    U32 slots_en = MAX_SLOTS_WANT;
    if (usb.max_slots < MAX_SLOTS_WANT) {
        slots_en = usb.max_slots;
    }
    MMIO_WRITE_U32(op_base + OP_CONFIG, slots_en);

    U32 sp_hi = (hcsparams2 >> 21) & 0x1F;
    U32 sp_lo = (hcsparams2 >> 27) & 0x1F;
    U32 max_scratch = (sp_hi << 5) | sp_lo;
    if (max_scratch > MAX_SCRATCHPAD) {
        max_scratch = MAX_SCRATCHPAD;
    }

    MemSet(usb.dcbaa, 0, sizeof(U64) * (MAX_SLOTS_WANT + 1));
    if (max_scratch > 0) {
        for (i = 0; i < max_scratch; i++) {
            MemSet(usb.scratch_buf[i], 0, 4096);
            usb.scratch_ptrs[i] = &usb.scratch_buf[i * 4096];
        }
        usb.dcbaa[0] = &usb.scratch_ptrs[0];
    }

    MMIO_WRITE_U64(op_base + OP_DCBAAP, &usb.dcbaa[0]);

    MemSet(usb.cmd.ring, 0, sizeof(CXhciTrb) * CMD_RING_TRBS);
    U64 ring_addr = &usb.cmd.ring[0];
    CXhciTrb* link = &usb.cmd.ring[CMD_RING_TRBS - 1];
    link->d0 = ring_addr & U32_MAX;
    link->d1 = (ring_addr >> 32) & U32_MAX;
    link->d2 = 0;
    link->d3 = (6 << 10) | (1 << 1) | 1;
    MMIO_WRITE_U64(op_base + OP_CRCR, (&usb.cmd.ring[0]) | 1);

    MemSet(usb.evt.ring, 0, sizeof(CXhciTrb) * EVT_RING_TRBS);
    usb.erst[0] = &usb.evt.ring[0];
    usb.erst[1] = EVT_RING_TRBS;
    MMIO_WRITE_U32(rt_base + RT_IR0_ERSTSZ, 1);
    MMIO_WRITE_U64(rt_base + RT_IR0_ERDP, &usb.evt.ring[0]);
    MMIO_WRITE_U64(rt_base + RT_IR0_ERSTBA, &usb.erst[0]);

    MMIO_WRITE_U32(op_base + OP_USBCMD, USBCMD_RUN);
    I32 started = 0;
    for (i = 0; i < 4000000; i++) {
        if (!(MMIO_READ_U32(op_base + OP_USBSTS) & USBSTS_HCH)) {
            started = 1;
            break;
        }
    }

    if (started) {

        for (p = 0; p < usb.max_ports; p++) {
            addr = op_base + OP_PORTSC_BASE + (p * 0x10);
            portsc = MMIO_READ_U32(addr);
            if (!(portsc & PORTSC_PP)) {
                MMIO_WRITE_U32(addr, portsc | PORTSC_PP);
            }
        }

        for (i = 0; i < 8000000; i++) {
            IntNop;
        }

        U32 iter, done;
        U32 ss_mask = XhciSsPortMask(hccparams1);

        for (p = 0; p < usb.max_ports; p++) {
            if (!(ss_mask & (1 << p)))
                goto cont_a;
            addr = op_base + OP_PORTSC_BASE + (p * 0x10);
            portsc = MMIO_READ_U32(addr);
            if (!(portsc & PORTSC_CCS)) {
                MMIO_WRITE_U32(addr, (portsc & PORTSC_PP) | (1 << 31));
            }
        cont_a:
        }

        for (iter = 0; iter < 220; iter++) {
            done = 0;
            if (ss_mask) {
                for (p = 0; p < usb.max_ports; p++) {
                    if (!(ss_mask & (1 << p)))
                        goto cont_b;
                    addr = op_base + OP_PORTSC_BASE + (p * 0x10);
                    if (MMIO_READ_U32(addr) & PORTSC_CCS) {
                        done = 1;
                        break;
                    }
                }
            } else {
                for (p = 0; p < usb.max_ports; p++) {
                    addr = op_base + OP_PORTSC_BASE + (p * 0x10);
                    if (MMIO_READ_U32(addr) & PORTSC_CCS) {
                        done = 1;
                        break;
                    }
                }
            }
            if (done) {
                break;
            }
            for (i = 0; i < 1000000; i++) {
                IntNop;
            }
        cont_b:
        }

        for (p = 0; p < usb.max_ports; p++) {
            addr = op_base + OP_PORTSC_BASE + (p * 0x10);
            portsc = MMIO_READ_U32(addr);
            MMIO_WRITE_U32(addr, (portsc & PORTSC_PP) | (1 << 17) | (1 << 19) | (1 << 21));
        }

        XhciDrainPendingEvents;
    }

    return started;
}