CDirEntry* de = (VOID*)(STD_ISO_PTR + 0xc980);
de->attr = 0x0c00;
MEMCPY((VOID*)&de->name, (VOID*)"Runtime.HC.Z", 12);
MEMCPY((VOID*)(STD_ISO_PTR + 0x108ba00), (VOID*)Runtime_HC_Z, Runtime_HC_Z_len);
de->clus = 0x845d;
de->size = Runtime_HC_Z_len;
}

void DoRuntimePatches()
{
    PatchStartOS();
    PatchRuntime();
}