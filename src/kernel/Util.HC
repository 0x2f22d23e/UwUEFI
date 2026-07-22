U0 PatchCallRel32(U32 from, U32 to)
{
    *(from(U8*)) = 0xe8;
    *((from + 1)(I32*)) = to - from - 5;
}

U0 PatchJmpRel32(U32 from, U32 to)
{
    *(from(U8*)) = 0xe9;
    *((from + 1)(I32*)) = to - from - 5;
}

U0 QMonOut(U8* fmt, ...)
{
    U8* buf = fmt;
    if (argc) {
        buf = StrPrintJoin(NULL, fmt, argc, argv);
        fmt = buf;
    }
    while (*buf) {
        OutU8(0x3f8, *buf++);
    }
    if (argc) {
        Free(fmt);
    }
}

U0 QMonSave(U8* file)
{
    CDirEntry* dt = FilesFind(file);
    if (!dt) {
        return;
    }
    CDirEntry* de = dt;
    CBlkDev* bd;
    I64 let;
    while (de) {
        let = *de->full_name;
        if (Let2BlkDevType(let) == BDT_RAM) {
            bd = Let2BlkDev(let);
            QMonOut("pmemsave 0x%08x 0x%08x %s\n", bd->RAM_dsk(U64) + (de->clus * BLK_SIZE), de->size, de->name);
        }
        de = de->next;
    }
    DirTreeDel(dt);
}