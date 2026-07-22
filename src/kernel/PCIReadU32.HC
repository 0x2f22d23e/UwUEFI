U32 _PCIReadU32(I64 bus, I64 dev, I64 fun, I64 rg)
{
    U32 address = (bus << 16) | (dev << 11) | (fun << 8) | (rg & 0xFC) | 0x80000000;
    OutU32(0xcf8, address);
    return InU32(0xcfc);
}

FileWrite("B:/PCIReadU32.BIN", &_PCIReadU32, sizeof(_PCIReadU32));
QMonSave("B:/PCIReadU32.BIN");
