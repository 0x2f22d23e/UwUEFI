#define pKbdCmdFlush 0x19b0b
#define pKbdCmdRead 0x19aa3
#define pKbdCmdSend 0x19a2b
#define pMsHardDrvrInstall 0x1bfdb

void PatchKbdCmdFlush()
{
    char* payload = "\x55\x48\x8b\xec\x5d\xc3";
    UINT32 len = 6;
    UINT8* dst = (VOID*)pKbdCmdFlush;
    COPY_PAYLOAD
}

void PatchKbdCmdRead()
{
    char* payload = "\x55\x48\x8b\xec\x33\xc0\x5d\xc3";
    UINT32 len = 8;
    UINT8* dst = (VOID*)pKbdCmdRead;
    COPY_PAYLOAD
}

void PatchKbdCmdSend()
{
    char* payload = "\x55\x48\x8b\xec\x5d\xc2\x10\x00";
    UINT32 len = 8;
    UINT8* dst = (VOID*)pKbdCmdSend;
    COPY_PAYLOAD
}

void PatchMsHardDrvrInstall()
{
    char* payload = "\x55\x48\x8b\xec\x33\xc0\x5d\xc2\x08\x00";
    UINT32 len = 10;
    UINT8* dst = (VOID*)pMsHardDrvrInstall;
    COPY_PAYLOAD
}

void DoLegacyKbdMsPatch()
{
    PatchKbdCmdFlush();
    PatchKbdCmdRead();
    PatchKbdCmdSend();
    PatchMsHardDrvrInstall();
}