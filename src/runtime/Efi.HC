class @gRT
{
    U64 hdr[3];
    U64 GetTime;
    U64 SetTime;
    U64 GetWakeupTime;
    U64 SetWakeupTime;
    U64 SetVirtualAddressMap;
    U64 ConvertPointer;
    U64 GetVariable;
    U64 GetNextVariableName;
    U64 SetVariable;
    U64 GetNextHighMonotonicCount;
    U64 ResetSystem;
    U64 UpdateCapsule;
    U64 QueryCapsuleCapabilities;
    U64 QueryVariableInfo;
};

class @gST
{
    U64 hdr[3];
    U16* vendor_str;
    U32 rev;
    U32 pad;
    U64 con[6];
    U64 runtime_svcs;
    U64 boot_svcs;
    U64 num_tbl_entries;
    U64 efi_cfg_tbl;
};

U0 EfiCall(U64 reg RBX, U64 reg RCX, U64 reg RDX, U64 reg R8, U64 reg R9)
{
    asm {
        CALL RBX
    }
}

U0 EfiReboot()
{
    CUefi* u = CORE0_32BIT_INIT;
    @gST* gST = u->sys_tbl_ptr;
    @gRT* gRT = gST->runtime_svcs;
    EfiCall(gRT->ResetSystem, 1, 0, 0, 0);
}

U0 EfiShutdown()
{
    CUefi* u = CORE0_32BIT_INIT;
    @gST* gST = u->sys_tbl_ptr;
    @gRT* gRT = gST->runtime_svcs;
    EfiCall(gRT->ResetSystem, 2, 0, 0, 0);
}

if (!IsKVM) {
    PatchJmpRel32(&Reboot, &EfiReboot);
}
