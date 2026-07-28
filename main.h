#include <Library/UefiBootServicesTableLib.h>
#include <Library/UefiLib.h>

#include <Protocol/LoadedImage.h>
#include <Protocol/SimpleFileSystem.h>

#define COPY_PAYLOAD                   \
    for (UINT32 i = 0; i < len; i++) { \
        dst[i] = payload[i];           \
    }

static inline UINT32
In32(
    IN UINT16 Port)
{
    UINT32 Data;

    __asm__ __volatile__(
        "inl %w1, %0"
        : "=a"(Data)
        : "d"(Port));

    return Data;
}

static inline VOID
Out32(
    IN UINT16 Port,
    IN UINT32 Data)
{
    __asm__ __volatile__(
        "outl %0, %w1"
        :
        : "a"(Data), "d"(Port));
}

#define MBS_UNUSED_SIGNATURE_VAL 0x6e55424d //'MBUn'
#define MEM_PAG_BITS 9

#define E820_LAST_ENTRY 7
#define GiB 0x40000000
#define MiB 0x200000

#define BOOT_INI_PTR 0x10000000
#define BOOT_EFI_PTR 0x10000400

#define CDIR_FILENAME_LEN 38
#define CORE0_32BIT_INIT 0x9F00 // repurposed for CUefi struct

#define STD_ISO_CRC32 0x1430e0ab
#define STD_ISO_PTR 0x10020000

#define KERNEL_BIN_SRC STD_ISO_PTR + 0xcc00
#define KERNEL_BIN_DST 0x7c00
#define KERNEL_BIN_SIZE 0x2e600

#define MEM_E801 0x7c40
#define MEM_E820 0x7c44

#define MEM_PHYSICAL_SPACE 0x8004

#define MEM_HEAP_BASE 0x9240
#define MEM_HEAP_LIMIT 0x9248
#define MEM_PAGE_SIZE 0x9250
#define MEM_MAPPED_SPACE 0x9258
#define MEM_2MEG_NUM 0x9260
#define MEM_1GIG_NUM 0x9268
#define MEM_512GIG_NUM 0x9270
#define MEM_PML2 0x9278
#define MEM_PML3 0x9280
#define MEM_PML4 0x9288

#define PCI_CFG_ADDR 0xCF8
#define PCI_CFG_DATA 0xCFC

#define SYS_FIXED_AREA 0x100000
#define SYS_16MEG_AREA_LIMIT 0x1000000
#define SYS_PCI_BUSES 0x8016

typedef struct {
    UINT16 attr;
    UINT8 name[CDIR_FILENAME_LEN];
    UINT64 clus;
    UINT64 size;
    UINT64 datetime;
} __attribute__((packed)) CDirEntry;

typedef struct {
    UINT64 next;
    UINT64 last;
    UINT32 mb_signature;
    UINT32 pags;
} __attribute__((packed)) CMemBlk;

typedef struct {
    UINT64 base;
    UINT64 len;
    UINT8 type;
    UINT8 pad[3];
} __attribute__((packed)) CMemE820;

typedef struct {
    UINT64 gop_fb_base;
    UINT32 gop_fb_size;
    UINT32 gop_fb_xres;
    UINT32 gop_fb_yres;
    UINT64 sys_tbl_ptr;
    UINT64 total_mem;
    UINT64 boot_efi_ptr;
    UINT32 boot_efi_size;
    UINT64 boot_ini_ptr;
    UINT32 boot_ini_size;
    BOOLEAN nvme_automount;
    UINT8 nvme_partition;
} __attribute__((packed)) CUefi;

typedef struct {
    UINT64 ptr;
    UINT32 size;
} CFileData;

struct __attribute__((packed)) {
    UINT16 Limit;
    UINT64 Base;
} GdtRecord, IdtRecord;

EFI_STATUS Status;

INT64 MEMCMP(UINT8* p1, UINT8* p2, UINT64 n)
{
    UINT8* s1 = p1;
    UINT8* s2 = p2;

    for (UINT64 i = 0; i < n; i++) {
        if (s1[i] != s2[i]) {
            return (s1[i] < s2[i]) ? -1 : 1;
        }
    }
    return 0;
}

void MEMCPY(UINT8* dst, UINT8* src, UINT64 cnt)
{
    for (UINT64 i = 0; i < cnt; i++) {
        dst[i] = src[i];
    }
}
void MEMSET(UINT8* dst, UINT8 val, UINT64 cnt)
{
    for (UINT64 i = 0; i < cnt; i++) {
        dst[i] = val;
    }
}

UINT64 ROUND_UP(UINT64 n, UINT64 multiple)
{
    return ((n + multiple - 1) / multiple) * multiple;
}

void STALL()
{
    while (1) {
        gBS->Stall(1000000);
    }
}

EFI_STATUS
ApplyPatch(
    IN VOID* OldBuf,
    IN UINTN OldSize,
    IN UINT8* PatchBuf,
    IN UINTN PatchSize,
    OUT VOID* NewBuf,
    OUT UINTN* NewSize)
{
    UINTN SrcIdx = 0;
    UINT8* Out = (UINT8*)NewBuf;
    UINT8* In = (UINT8*)OldBuf;

    if (OldBuf == NULL || PatchBuf == NULL || NewBuf == NULL || NewSize == NULL) {
        return EFI_INVALID_PARAMETER;
    }
    if (PatchSize < 4) {
        return EFI_BAD_BUFFER_SIZE;
    }

    UINT32 TargetFinalSize = *(UINT32*)(PatchBuf + SrcIdx);
    SrcIdx += 4;

    UINTN InitialCopy = (OldSize < (UINTN)TargetFinalSize) ? OldSize : (UINTN)TargetFinalSize;
    MEMCPY(Out, In, InitialCopy);

    if ((UINTN)TargetFinalSize > OldSize) {
        MEMSET(Out + OldSize, 0, (UINTN)TargetFinalSize - OldSize);
    }

    while (SrcIdx + 6 <= PatchSize) {
        UINT32 Offset = *(UINT32*)(PatchBuf + SrcIdx);
        UINT16 BlockLen = *(UINT16*)(PatchBuf + SrcIdx + 4);
        SrcIdx += 6;

        if (SrcIdx + BlockLen > PatchSize || (UINTN)Offset + BlockLen > (UINTN)TargetFinalSize) {
            return EFI_VOLUME_CORRUPTED;
        }

        if (BlockLen > 0) {
            MEMCPY(Out + Offset, PatchBuf + SrcIdx, BlockLen);
            SrcIdx += BlockLen;
        }
    }

    *NewSize = (UINTN)TargetFinalSize;
    return EFI_SUCCESS;
}

UINT64 GetTotalMemory()
{
    UINTN MemoryMapSize = 0;
    EFI_MEMORY_DESCRIPTOR* MemoryMap = NULL;
    UINTN MapKey;
    UINTN DescriptorSize;
    UINT32 DescriptorVersion;

    Status = gBS->GetMemoryMap(
        &MemoryMapSize,
        NULL,
        &MapKey,
        &DescriptorSize,
        &DescriptorVersion);

    if (Status != EFI_BUFFER_TOO_SMALL) {
        return 0;
    }
    MemoryMapSize += (2 * DescriptorSize);
    Status = gBS->AllocatePool(
        EfiLoaderData,
        MemoryMapSize,
        (VOID**)&MemoryMap);
    if (EFI_ERROR(Status)) {
        return 0;
    }

    Status = gBS->GetMemoryMap(
        &MemoryMapSize,
        MemoryMap,
        &MapKey,
        &DescriptorSize,
        &DescriptorVersion);
    if (EFI_ERROR(Status)) {
        gBS->FreePool(MemoryMap);
        return 0;
    }

    UINT8* EntryPtr = (UINT8*)MemoryMap;
    UINTN TotalEntries = MemoryMapSize / DescriptorSize;
    UINT64 TotalBytes = 0;

    for (UINTN i = 0; i < TotalEntries; i++) {
        EFI_MEMORY_DESCRIPTOR* Desc = (EFI_MEMORY_DESCRIPTOR*)EntryPtr;
        UINT64 EntryBytes = (UINT64)Desc->NumberOfPages * 4096ULL;
        TotalBytes += EntryBytes;
        EntryPtr += DescriptorSize;
    }

    gBS->FreePool(MemoryMap);
    return TotalBytes;
}
