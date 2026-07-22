U16 _PCIReadU16(I64 bus, I64 dev, I64 fun, I64 rg)
{
    U32 address = (bus << 16) | (dev << 11) | (fun << 8) | (rg & 0xfc) | 0x80000000;
    OutU32(0xcf8, address);
    return (InU32(0xcfc) >> ((rg & 2) * 8)) & 0xffff;
}

FileWrite("B:/PCIReadU16.BIN", &_PCIReadU16, sizeof(_PCIReadU16));
QMonSave("B:/PCIReadU16.BIN");
