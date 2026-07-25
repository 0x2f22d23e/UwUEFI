#define UEFI_DISK_OFFSET 0x10020000
#define UEFI_DISK_SIZE 0x118c000 // Size of TempleOS.ISO and <1MB Runtime payload
#define RAM_DISK_SIZE 0x4000000

U0 _BlkDevsInitAll()
{
    I64 reg RDI i;
    I64 reg RDX drvs;

    drvs = CAlloc(0x1cd8);
    MemSetI64(0xbc70, drvs, 1);          // blkdev.drvs
    MemSetI64(0xbc18, drvs + 0x1040, 1); // blkdev.blkdevs

    // blkdev.let_to_drv[i] = &blkdev.drvs[i];
    for (i = 0; i < DRVS_NUM; i++) {
        MemSetI64(0xbc78 + (i * 8), drvs + (i * 0xa0), 1);
    }

    // Create 64MB RAM disk for boot filesystem
    CDrv* dv = DrvMakeFreeSlot('A');
    CBlkDev* bd = BlkDevNextFreeSlot(dv->drv_let, BDT_RAM);
    bd->max_blk = (RAM_DISK_SIZE / BLK_SIZE) - 1;
    BlkDevAdd(bd, , FALSE, FALSE);

    // Set ISO's root_clus and copy the filesystem
    dv->root_clus = 0x62;
    dv->data_area = 0x61;
    MemCpy(bd->RAM_dsk(U64) + (0xc200), UEFI_DISK_OFFSET + (0xc200), UEFI_DISK_SIZE);

    // blkdev.boot_drv_let = 'A';
    MemSetU8(0xbd90, 'A', 1);
    MemSetU8(SYS_BOOT_SRC, BOOT_SRC_RAM, 1);
}

MemSet(&BlkDevsInitAll, 0x90, sizeof(BlkDevsInitAll));
MemCpy(&BlkDevsInitAll, &_BlkDevsInitAll, sizeof(_BlkDevsInitAll));
PatchCallRel32(&BlkDevsInitAll + 0x13, &CAlloc);
PatchCallRel32(&BlkDevsInitAll + 0x23, &MemSetI64);
PatchCallRel32(&BlkDevsInitAll + 0x37, &MemSetI64);
PatchCallRel32(&BlkDevsInitAll + 0x5d, &MemSetI64);
PatchCallRel32(&BlkDevsInitAll + 0x69, &DrvMakeFreeSlot);
PatchCallRel32(&BlkDevsInitAll + 0x7a, &BlkDevNextFreeSlot);
PatchCallRel32(&BlkDevsInitAll + 0x9a, &BlkDevAdd);
PatchCallRel32(&BlkDevsInitAll + 0xc5, &MemCpy);
PatchCallRel32(&BlkDevsInitAll + 0xd3, &MemSetU8);
PatchCallRel32(&BlkDevsInitAll + 0xe1, &MemSetU8);

FileWrite("B:/BlkDevsInitAll.BIN", &BlkDevsInitAll, sizeof(BlkDevsInitAll));
QMonSave("B:/BlkDevsInitAll.BIN");
