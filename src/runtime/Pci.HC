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

U0 PciEnableBusMaster(I64 d)
{
    U16 v = PCIReadU16(d.u8[2], d.u8[1], d.u8[0], 0x04);
    v = v | 1 << 2;
    PCIWriteU16(d.u8[2], d.u8[1], d.u8[0], 0x04, v);
}
