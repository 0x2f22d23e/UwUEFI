#define NVME_DEFAULT_BAR0 0xdc000000
#define NVME_DEV nvme.dev.u8[2], nvme.dev.u8[1], nvme.dev.u8[0]

#define NVME_CALLOC_PAGE CAllocAligned(0x1000, 0x1000, adam_task->code_heap)
#define NVME_CLEAR_SQ_ENTRY MemSet(cmd, 0, sizeof(NvmeSqEntry));

#define NVME_REG_CAP nvme.bar0 + 0x0000
#define NVME_REG_CC nvme.bar0 + 0x0014
#define NVME_REG_CSTS nvme.bar0 + 0x001c
#define NVME_REG_AQA nvme.bar0 + 0x0024
#define NVME_REG_ASQ nvme.bar0 + 0x0028
#define NVME_REG_ACQ nvme.bar0 + 0x0030

#define NVME_CC_EN (1 << 0)
#define NVME_CSTS_RDY (1 << 0)

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
    if (nvme.status < 0) {
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
        Sleep(1);
    }

    U16 raw_status = (nvme.admin_cq[nvme.admin_cq_head](U16*) + 0x07)[0];
    U16 status = (raw_status >> 1) & 0x7FFF;
    if (status != 0) {
        nvme.status = -2;
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

U0 NvmeBlkOp(U32 nsid, U64 lba, U64 buf, Bool is_write)
{
    NvmeSqEntry* cmd = &nvme.io_sq[nvme.io_sq_tail];
    NVME_CLEAR_SQ_ENTRY

    cmd->opcode = 0x02 - (is_write);
    cmd->nsid = nsid;
    cmd->cid = nvme.io_sq_tail;
    cmd->prp1 = nvme.blk_buf;
    cmd->prp2 = 0;

    cmd->cdw10[0] = lba & U32_MAX;
    cmd->cdw10[1] = (lba >> 32) & U32_MAX;
    cmd->cdw10[2] = 0; // num of blks, zero-indexed

    if (is_write) {
        MemCpy(nvme.blk_buf, buf, BLK_SIZE);
    }

    nvme.io_sq_tail = (nvme.io_sq_tail + 1) % 64;
    NvmeWriteDoorbell(1, 0, nvme.io_sq_tail);

    while ((nvme.io_cq[nvme.io_cq_head].status & 1) != nvme.io_cq_phase) {
        Sleep(1);
    }

    nvme.io_cq_head = (nvme.io_cq_head + 1) % 64;
    if (nvme.io_cq_head == 0) {
        nvme.io_cq_phase ^= 1;
    }
    NvmeWriteDoorbell(1, 1, nvme.io_cq_head);

    if (!is_write) {
        MemCpy(buf, nvme.blk_buf, BLK_SIZE);
    }
}

I64 NvmeInit()
{
    MemSet(&nvme, 0, sizeof(@nvme));
    nvme.dev = PCIClassFind(0x010802, 0);

    if (nvme.dev == -1) {
        nvme.status = -1;
        StrCpy(&nvme.err_msg, "Controller not found");
        goto nvme_init_end;
    }

    nvme.blk_buf = NVME_CALLOC_PAGE;
    nvme.ns_info = NVME_CALLOC_PAGE;
    nvme.admin_cq_phase = 1;
    nvme.io_cq_phase = 1;
    nvme.nsid = 1;

    PciEnableBusMaster(nvme.dev);
    NvmeConfigBar0;
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
    StrCpy(&nvme.err_msg, "Init success");

nvme_init_end:
    return nvme.status;
}
