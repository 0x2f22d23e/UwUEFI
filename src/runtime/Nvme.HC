#define NVME_DEFAULT_BAR0 0xdc000000
#define NVME_DEV nvme.dev.u8[2], nvme.dev.u8[1], nvme.dev.u8[0]

#define NVME_CALLOC_2M CAllocAligned(0x200000, 0x1000, adam_task->code_heap);
#define NVME_CALLOC_16K CAllocAligned(0x4000, 0x1000, adam_task->code_heap);
#define NVME_CALLOC_PAGE CAllocAligned(0x1000, 0x1000, adam_task->code_heap);

#define NVME_CLEAR_SQ_ENTRY MemSet(cmd, 0, sizeof(NvmeSqEntry));
#define NVME_MAX_RW_BLK 512

#define NVME_REG_CAP nvme.bar0 + 0x0000
#define NVME_REG_CC nvme.bar0 + 0x0014
#define NVME_REG_CSTS nvme.bar0 + 0x001c
#define NVME_REG_AQA nvme.bar0 + 0x0024
#define NVME_REG_ASQ nvme.bar0 + 0x0028
#define NVME_REG_ACQ nvme.bar0 + 0x0030

#define NVME_CC_EN (1 << 0)
#define NVME_CSTS_RDY (1 << 0)

#define NVME_S_ERR -1
#define NVME_S_NULL 0
#define NVME_S_OK 1

class NvmeIdentifyNS {
    U64 nsze;
    U64 ncap;
    U64 nuse;
    U8 nsfeat;
    U8 nlbaf;
    U8 flbas;
    U8 reserved[101];
    U32 lbaf[16];
};

class NvmeSqEntry {
    U8 opcode;
    U8 flags;
    U16 cid;
    U32 nsid;
    U64 rsvd1;
    U64 mptr;
    U64 prp1;
    U64 prp2;
    U32 cdw10[6];
};

class NvmeCqEntry {
    U32 result;
    U32 rsvd;
    U16 sq_head;
    U16 sq_id;
    U16 cid;
    U16 status;
};

class @nvme
{
    I64 dev;
    U16 cid;
    U32 bar0;
    U32 nsid;
    I64 db_stride;
    NvmeSqEntry* admin_sq;
    NvmeCqEntry* admin_cq;
    U16 admin_sq_tail;
    U16 admin_cq_head;
    U8 admin_cq_phase;
    NvmeSqEntry* io_sq;
    NvmeCqEntry* io_cq;
    U16 io_sq_tail;
    U16 io_cq_head;
    U8 io_cq_phase;
    U8* blk_buf;
    U8* work_buf;
    U64* prp_list;
    NvmeIdentifyNS* ns_info;
    I64 blk_size;
    I64 capacity;
    I64 status;
    U8 err_msg[128];
}
nvme;

U0 NvmeConfigBar0()
{
    if (IsKVM || PCIReadU32(NVME_DEV, 0x14)) {
        PCIWriteU32(NVME_DEV, 0x10, NVME_DEFAULT_BAR0);
        PCIWriteU32(NVME_DEV, 0x14, 0);
    }
    nvme.bar0 = PCIReadU32(NVME_DEV, 0x10) & ~0xfc;
}

U0 NvmeConfigPrpList()
{
    I64 i;
    for (i = 1; i < NVME_MAX_RW_BLK; i++) {
        nvme.prp_list[i - 1] = nvme.blk_buf(U64) + (0x1000 * i);
    }
}

U0 NvmeSetDoorbellStride()
{
    U64 cap = *(NVME_REG_CAP)(U64*);
    nvme.db_stride = 1 << (2 + ((cap >> 32) & 0xf));
}

U0 NvmeDisableController()
{
    *(NVME_REG_CC)(U32*) &= ~NVME_CC_EN;
    while (*(NVME_REG_CSTS)(U32*)&NVME_CSTS_RDY) {
        Sleep(1);
    }
}

U0 NvmeEnableController()
{
    *(NVME_REG_CC)(U32*) = 0x00460001;
    while (!(*(NVME_REG_CSTS)(U32*)&NVME_CSTS_RDY)) {
        Sleep(1);
    }
}

U0 NvmeWriteDoorbell(U32 qid, Bool is_cq, U16 val)
{
    U32 _offset = 0x1000 + ((qid * 2) + is_cq) * nvme.db_stride;
    *(nvme.bar0 + _offset)(U32*) = val;
}

U0 NvmeConfigAdminQueues()
{
    nvme.admin_sq = NVME_CALLOC_PAGE;
    nvme.admin_cq = NVME_CALLOC_PAGE;

    *(NVME_REG_AQA)(U32*) = (63 << 16) | 63;
    *(NVME_REG_ASQ)(U64*) = nvme.admin_sq;
    *(NVME_REG_ACQ)(U64*) = nvme.admin_cq;
}

U0 NvmeDoAdminCmd(I64 opcode, U32 nsid, U64 prp1, U32 dw10, U32 dw11)
{
    if (nvme.status < NVME_S_NULL) {
        return;
    }

    NvmeSqEntry* cmd = &nvme.admin_sq[nvme.admin_sq_tail];
    NVME_CLEAR_SQ_ENTRY
    cmd->opcode = opcode;
    cmd->cid = nvme.cid++;
    cmd->nsid = nsid;
    cmd->prp1 = prp1;
    cmd->cdw10[0] = dw10;
    cmd->cdw10[1] = dw11;

    // "NvmeDoAdminCmd Payload:\n";
    // D(&nvme.admin_sq[nvme.admin_sq_tail], sizeof(NvmeSqEntry));

    nvme.admin_sq_tail = (nvme.admin_sq_tail + 1) % 64;
    NvmeWriteDoorbell(0, 0, nvme.admin_sq_tail);

    while ((nvme.admin_cq[nvme.admin_cq_head].status & 1) != nvme.admin_cq_phase) {
        Yield;
    }

    U16 raw_status = (nvme.admin_cq[nvme.admin_cq_head](U16*) + 0x07)[0];
    U16 status = (raw_status >> 1) & 0x7FFF;
    if (status != 0) {
        nvme.status = NVME_S_ERR;
        StrPrint(&nvme.err_msg, "NvmeDoAdminCmd failed; opcode=0x%02x, status=0x%04x");
        return;
    }

    nvme.admin_cq_head = (nvme.admin_cq_head + 1) % 64;
    NvmeWriteDoorbell(0, 1, nvme.admin_cq_head);

    if (nvme.admin_cq_head == 0) {
        nvme.admin_cq_phase ^= 1;
    }

    // "NvmeDoAdminCmd Status: 0x%X\n", nvme.admin_cq[(nvme.admin_cq_head - 1) & 63].status;
}

U0 NvmeSetFeatures()
{
    NvmeDoAdminCmd(0x09, 0, NULL, 0x07, 0x00); // DW10: Set Number of Queues; DW11: 0h, 0l = 1cq, 1sq
    NvmeDoAdminCmd(0x09, 0, NULL, 0x06, 0x00); // DW10: Set Volatile Write Cache; DW11: Disabled
}

U0 NvmeConfigIoQueues()
{
    nvme.io_sq = NVME_CALLOC_PAGE;
    nvme.io_cq = NVME_CALLOC_PAGE;
    U32 dw10;
    U32 dw11;

    /* cqid, qsize, cq_flags, irq_vector */
    dw10.u16[0] = 1;
    dw10.u16[1] = 63;
    dw11.u16[0] = 1;
    dw11.u16[1] = 0;
    NvmeDoAdminCmd(0x05, 0, nvme.io_cq, dw10, dw11);

    /* sqid, qsize, sq_flags, cqid */
    dw10.u16[0] = 1;
    dw10.u16[1] = 63;
    dw11.u16[0] = 1;
    dw11.u16[1] = 1;
    NvmeDoAdminCmd(0x01, 0, nvme.io_sq, dw10, dw11);
}

U0 NvmeIdentify(U32 nsid)
{
    NvmeDoAdminCmd(0x06, nsid, nvme.ns_info, 0, 0);
    // ClassRep(nvme.ns_info);
}

U0 NvmeUpdateNSInfo()
{
    NvmeIdentify(nvme.nsid);
    I64 fmt = nvme.ns_info->flbas & 0x0f;
    I64 lbads = (nvme.ns_info->lbaf[fmt] >> 16) & 0xff;
    nvme.blk_size = (1 << lbads);
    nvme.capacity = nvme.ns_info->nsze * nvme.blk_size;
}

U0 NvmeBlkOp(U32 nsid, U64 lba, U64 buf, I64 cnt, Bool is_write)
{
    NvmeSqEntry* cmd = &nvme.io_sq[nvme.io_sq_tail];
    NVME_CLEAR_SQ_ENTRY
    MemSet(nvme.blk_buf, 0, BLK_SIZE * cnt);

    cmd->opcode = 0x02 - (is_write);
    cmd->nsid = nsid;
    cmd->cid = nvme.io_sq_tail;
    cmd->prp1 = nvme.blk_buf;
    if (cnt > 16) {
        cmd->prp2 = nvme.prp_list;
    } else if (cnt > 8) {
        cmd->prp2 = nvme.blk_buf(U64) + 0x1000;
    } else {
        cmd->prp2 = 0;
    }

    cmd->cdw10[0] = lba & U32_MAX;
    cmd->cdw10[1] = (lba >> 32) & U32_MAX;
    cmd->cdw10[2] = cnt - 1; // num of blks, zero-indexed

    if (is_write) {
        MemCpy(nvme.blk_buf, buf, BLK_SIZE * cnt);
    }

    nvme.io_sq_tail = (nvme.io_sq_tail + 1) % 64;
    NvmeWriteDoorbell(1, 0, nvme.io_sq_tail);

    while ((nvme.io_cq[nvme.io_cq_head].status & 1) != nvme.io_cq_phase) {
        Yield;
    }

    nvme.io_cq_head = (nvme.io_cq_head + 1) % 64;
    if (nvme.io_cq_head == 0) {
        nvme.io_cq_phase ^= 1;
    }
    NvmeWriteDoorbell(1, 1, nvme.io_cq_head);

    if (!is_write) {
        MemCpy(buf, nvme.blk_buf, BLK_SIZE * cnt);
    }
}

I64 NvmeInit()
{
    switch (nvme.status) {
    case NVME_S_ERR:
    case NVME_S_OK:
        goto nvme_init_end;
    default:
        break;
    }

    nvme.dev = PCIClassFind(0x010802, 0);

    if (nvme.dev == -1) {
        nvme.status = NVME_S_ERR;
        StrCpy(&nvme.err_msg, "Controller not found");
        goto nvme_init_end;
    }

    nvme.blk_buf = NVME_CALLOC_2M;
    nvme.work_buf = NVME_CALLOC_16K;
    nvme.ns_info = NVME_CALLOC_PAGE;
    nvme.prp_list = NVME_CALLOC_PAGE;
    nvme.admin_cq_phase = 1;
    nvme.io_cq_phase = 1;
    nvme.nsid = 1;

    PciEnableBusMaster(nvme.dev);
    NvmeConfigBar0;
    NvmeConfigPrpList;
    NvmeSetDoorbellStride;
    NvmeDisableController;
    NvmeConfigAdminQueues;
    NvmeEnableController;
    NvmeSetFeatures;
    NvmeConfigIoQueues;
    if (nvme.status) {
        goto nvme_init_end;
    }
    NvmeUpdateNSInfo;
    nvme.status = NVME_S_OK;
    StrCpy(&nvme.err_msg, "Init success");

nvme_init_end:
    return nvme.status;
}

// Patch over BDT_ATA and BDT_ATAPI

Bool _ATARBlks(CDrv* dv, U8* buf, I64 blk, I64 cnt)
{
    I64 n;
    while (cnt > 0) {
        n = cnt;
        if (n > NVME_MAX_RW_BLK) {
            n = NVME_MAX_RW_BLK;
        }
        NvmeBlkOp(nvme.nsid, blk, buf, n, 0);
        buf += n << BLK_SIZE_BITS;
        blk += n;
        cnt -= n;
    }
    return TRUE;
}

Bool _ATAWBlks(CDrv* dv, U8* buf, I64 blk, I64 cnt)
{
    I64 n;
    while (cnt > 0) {
        n = cnt;
        if (n > NVME_MAX_RW_BLK) {
            n = NVME_MAX_RW_BLK;
        }
        NvmeBlkOp(nvme.nsid, blk, buf, n, 1);
        buf += n << BLK_SIZE_BITS;
        blk += n;
        cnt -= n;
    }
    return TRUE;
}

PatchJmpRel32(&ATARBlks, &_ATARBlks);
PatchJmpRel32(&ATAWBlks, &_ATAWBlks);
MemCpy(&ATAInit, "\x55\x48\x8b\xec\x33\xc0\xb0\x01\x5d\xc2\x08\x00", 0x0c);

#define GiB 0x40000000
#define MiB 0x100000

#define BDT_NVME BDT_ATAPI
StrCpy(DefineSub(BDT_NVME, "ST_BLKDEV_TYPES"), "NVME");

Bool NvmeChk()
{
    NvmeInit;
    return nvme.status == NVME_S_OK;
}

U0 NvmeListPartitions()
{
    U8* buf = nvme.work_buf;
    _ATARBlks(NULL, buf, 1, 1);
    U32* hdr = buf;
    U8 guid[38];

    U32 cnt = hdr[0x14];
    U32 entry_size = hdr[0x15];
    I64 blks = (cnt * entry_size) / BLK_SIZE;
    _ATARBlks(NULL, buf, 2, blks);

    I64 i;
    I64 size;
    I64 unit;
    CGptEntry* e = buf;
    for (i = 0; i < cnt; i++) {
        if (e->type_lo) {
            "Partition %d\n", i + 1;
            MakeGuid(guid, e);
            "  type: %s (%s)\n", guid, GptType(guid);
            MakeGuid(guid, e(U64) + 0x10);
            "    id: %s\n", guid;
            size = (e->lba_end - e->lba_start) * BLK_SIZE;
            if (size >= GiB) {
                size /= GiB;
                unit = 'G';
            } else {
                size /= MiB;
                unit = 'M';
            }
            "  size: %04d%c (start=0x%08x, end=0x%08x), flags: 0x%08x\n", size, unit, e->lba_start, e->lba_end, e->flags;
            "  name: ";
            LPutS(&e->wname);
            "\n";
        }
        e++;
    }
}

U0 NvmeScan()
{
    if (!NvmeChk) {
        PrintErr("NvmeScan: %s\n", nvme.err_msg);
        return;
    }

    _ATARBlks(NULL, nvme.work_buf, 0, 1);
    if (IsGpt(nvme.work_buf)) {
        "Gpt partition table found\n";
        NvmeListPartitions;
    } else {
        "No supported partition table found\n";
    }
}

U0 NvmeI_BuildEfi()
{
    CUefi* u = CORE0_32BIT_INIT;
    U8* boot_opt = "\nCrcCheck=off\nNvmeAutoMount=on\nNvmePartition=2";
    RamDisk('B', (64 * MiB), FSt_FAT32);
    DirMk("B:/EFI");
    DirMk("B:/EFI/BOOT");
    if (u->boot_ini_ptr && u->boot_ini_size) {
        StrCpy(u->boot_ini_ptr + u->boot_ini_size, boot_opt);
    } else {
        u->boot_ini_ptr = boot_opt;
    }
    u->boot_ini_size += StrLen(boot_opt);
    FileWrite("B:/boot.ini", u->boot_ini_ptr, u->boot_ini_size);
    FileWrite("B:/EFI/BOOT/BOOTX64.EFI", u->boot_efi_ptr, u->boot_efi_size);
    FileWrite("B:/TempleOS.ISO", Let2BlkDev('A')->RAM_dsk, (48 * MiB));
}

U0 NvmeI_WriteMBR()
{
    U8* buf = nvme.work_buf;
    MemSet(buf, 0, BLK_SIZE);
    MemCpy(buf + 0x01c0, "\x02\x00\xee\xff\xff\xff\x01\x00\x00\x00\xff\xff\x01\x00\x00\x00", 0x10);
    buf(CMasterBoot*)->signature = 0xaa55;
    _ATAWBlks(NULL, buf, 0, 1);
}

U0 NvmeI_WriteGPT()
{
    U8* buf = nvme.work_buf;

    U32 hdr_crc = 0;
    U32 pe_crc = 0;

    U32 pe_cnt = 128;
    U32 pe_size = 128;

    // write the GPT PE
    MemSet(buf, 0, (pe_cnt * pe_size));
    CGptEntry* e = buf;

    MemCpy(e, "\x28\x73\x2a\xc1\x1f\xf8\xd2\x11\xba\x4b\x00\xa0\xc9\x3e\xc9\x3b", 0x10);
    StrCpy(&e->id_lo, "PartGuidGoesHere");
    e->lba_start = 0x800;
    e->lba_end = 0x1f7ff;
    e++;

    MemCpy(e, "TempleOS RedSea", 0x10);
    StrCpy(&e->id_lo, "RingZeroRingZero");
    e->lba_start = 0x1f800;
    e->lba_end = 0x21f7ff;

    I64 blks = (pe_cnt * pe_size) / BLK_SIZE;
    _ATAWBlks(NULL, buf, 2, blks);
    pe_crc = Crc32(buf, (pe_cnt * pe_size));

    // write the GPT header
    MemSet(buf, 0, BLK_SIZE);
    CGptHeader* gpt = buf;
    StrCpy(gpt, "EFI PART");
    gpt->revision = 0x10000;
    gpt->hdr_size = 0x5c;
    gpt->crc32 = 0;
    gpt->this_hdr = 0x01; // block
    gpt->alt_hdr = 0x04ffff;
    gpt->first_lba = 0x800;
    gpt->last_lba = 0x01ffed;
    StrCpy(&gpt->diskid_lo, "DiskGuidGoesHere");
    gpt->pe_lba = 0x02; // block
    gpt->pe_cnt = pe_cnt;
    gpt->pe_size = pe_size;
    gpt->pe_crc32 = pe_crc;
    hdr_crc = Crc32(buf, gpt->hdr_size);
    gpt->crc32 = hdr_crc;
    _ATAWBlks(NULL, buf, 1, 1);
}

Bool NvmeMount(I64 let, I64 p, Bool init)
{
    if (!NvmeChk) {
        PrintErr("NvmeMount: %s\n", nvme.err_msg);
        return 0;
    }

    U8* buf = nvme.work_buf;

    _ATARBlks(NULL, buf, 0, 1);
    if (!IsGpt(buf)) {
        "No supported partition table found\n";
        return 0;
    }

    _ATARBlks(NULL, buf, 1, 1);
    CGptHeader* gpt = buf;

    I64 blks = (gpt->pe_cnt * gpt->pe_size) / BLK_SIZE;
    _ATARBlks(NULL, buf, 2, blks);
    CGptEntry* e = buf;
    I64 i = 0;
    while (i < p - 1) {
        e++;
        i++;
    }

    CDrv* dv = DrvMakeFreeSlot(let);
    CBlkDev* bd = BlkDevNextFreeSlot(dv->drv_let, BDT_NVME);
    bd->max_blk = (MinI64(nvme.capacity, GiB << 4) / BLK_SIZE) - 1;
    BlkDevAdd(bd, , FALSE, FALSE);

    dv->drv_offset = e->lba_start;
    dv->size = GiB / BLK_SIZE;
    dv->fat2 = dv->fat1 = dv->drv_offset + 0x01;

    if (init) {
        dv->data_area = dv->drv_offset + 0x100;
        dv->root_clus = dv->data_area + 0x01;
    } else {
        _ATARBlks(NULL, buf, dv->drv_offset, 1);
        if (buf[3] != MBR_PT_REDSEA) {
            BlkDevDel(bd);
            return 0;
        }
        dv->data_area = (buf)(U64*)[1];
        dv->root_clus = (buf)(U64*)[3];
    }

    bd->flags &= ~BDF_READ_ONLY;
    bd->flags &= ~BDF_READ_CACHE;
    dv->fs_type = FSt_REDSEA;

    if (init) {
        CallExtStr("RedSeaFmt", let, 1);
    }

    return let;
}

U0 NvmeInstall()
{
    if (!NvmeChk) {
        PrintErr("NvmeInstall: %s\n", nvme.err_msg);
        return;
    }

    "\dFG,RED\d\dIV,1\d\dBK,1\dWARNING:\dIV,0\d\dBK,0\d ";
    "\dFG,BLACK\dThis will: wipe the contents of the NVMe drive, install a new GPT, create a 64MB EFI partition w/ TempleOS.ISO and bootloader, and a 1GB RedSea partition.\n\n";
    "\dFG,RED\d\dIV,1\d\dBK,1\dARE YOU SURE?\dIV,0\d\dBK,0\d ";

    if (!YorN) {
        return;
    }

    "\dFD\d";

    "**** Building EFI filesystem\n";
    NvmeI_BuildEfi;

    "**** Writing MBR\n";
    NvmeI_WriteMBR;

    "**** Writing GPT\n";
    NvmeI_WriteGPT;

    "**** Writing EFI filesystem\n";
    _ATAWBlks(NULL, Let2BlkDev('B')->RAM_dsk, 0x800, ((48 * MiB) / BLK_SIZE));

    BlkDevDel(Let2BlkDev('B'));

    "**** Format RedSea partition\n";
    NvmeMount('T', 2, TRUE);

    "**** Installing TempleOS\n";
    CopyTree("A:/", "T:/");

    "OK to Reboot? ";

    if (YorN) {
        Reboot;
    }
}

U0 NvmeAutoMount()
{
    if (!NvmeChk) {
        return;
    }

    CUefi* u = CORE0_32BIT_INIT;
    if (!u->nvme_automount || !u->nvme_partition) {
        return;
    }

    I64 let = NvmeMount('T', u->nvme_partition, FALSE);
    if (let) {
        blkdev.home_dir[0] = let;
    }
}

MemSet(&nvme, 0, sizeof(@nvme));
NvmeAutoMount;