/* clang-format off */
#include "main.h"
#include "ini.c"
#include "patches/build_type.c"
#include "patches/runtime.c"
/* clang-format on */

CHAR16* IniFilePath = L"\\boot.ini";
CHAR16* IsoFilePath = L"\\TempleOS.ISO";
UINT64 MaxTotalMemory = 0;
BOOLEAN SkipCrcCheck = FALSE;

EFI_STATUS ExitUefi(EFI_HANDLE ImageHandle)
{
    UINTN MemoryMapSize = 0;
    EFI_MEMORY_DESCRIPTOR* MemoryMap = NULL;
    UINTN MapKey = 0;
    UINTN DescriptorSize = 0;
    UINT32 DescriptorVersion = 0;

    gBS->GetMemoryMap(&MemoryMapSize, MemoryMap, &MapKey, &DescriptorSize,
        &DescriptorVersion);

    return gBS->ExitBootServices(ImageHandle, MapKey);
}

UINT64 LoadFileAtAddress(EFI_FILE_HANDLE Root, CHAR16* FileName, UINT64 Address, BOOLEAN StallOnError)
{
    EFI_FILE_HANDLE File;
    UINTN FileSize = 0xffffffff;
    Status = Root->Open(Root, &File, FileName, EFI_FILE_MODE_READ, 0);
    if (EFI_ERROR(Status)) {
        if (StallOnError) {
            Print(L"ERROR: Could not load file '%s' at memory address: 0x%08x: %r\r\n", FileName, Address, Status);
            STALL();
        } else {
            return FileSize;
        }
    }
    File->Read(File, &FileSize, (VOID*)Address);
    File->Close(File);
    return FileSize;
}

void ParseIniFile(UINT64 FileSize)
{
    if (FileSize == 0xFFFFFFFF) {
        return;
    }

    CHAR8 key[256];
    CHAR8 value[256];
    UINT64 i = 0;
    UINT64 u64 = 0;

    while (ParseIniKeyValue(STD_ISO_PTR, FileSize, (UINT8*)&key, (UINT8*)&value, &i)) {
        if (!MEMCMP((UINT8*)&key, (UINT8*)"IsoFilePath", 11)) {
            IsoFilePath = CatSPrint(NULL, L"%a", (CHAR8*)&value);
        }
        if (!MEMCMP((UINT8*)&key, (UINT8*)"MaxTotalMemory", 9)) {
            if (ParseIniU64((CHAR8*)&value, (UINT64*)&u64)) {
                MaxTotalMemory = (u64 >= 1024 && u64 <= 131072) ? (u64 * 0x100000) : 0;
            }
        };
        // Print(L"Key: '%a', Value: '%a'\n", key, value);
    }
}

void LoadOperatingSystemFiles()
{
    EFI_LOADED_IMAGE_PROTOCOL* LoadedImage;
    EFI_SIMPLE_FILE_SYSTEM_PROTOCOL* Fs;
    EFI_FILE_HANDLE Root;
    UINT64 FileSize;
    UINT32 Crc32;

    gBS->HandleProtocol(gImageHandle, &gEfiLoadedImageProtocolGuid,
        (VOID**)&LoadedImage);
    gBS->HandleProtocol(LoadedImage->DeviceHandle,
        &gEfiSimpleFileSystemProtocolGuid, (VOID**)&Fs);
    Fs->OpenVolume(Fs, &Root);

    FileSize = LoadFileAtAddress(Root, IniFilePath, STD_ISO_PTR, FALSE);
    ParseIniFile(FileSize);

    FileSize = LoadFileAtAddress(Root, IsoFilePath, STD_ISO_PTR, TRUE);
    if (!SkipCrcCheck) {
        Crc32 = CalculateCrc32((VOID*)STD_ISO_PTR, FileSize);
        if (Crc32 != STD_ISO_CRC32) {
            Print(L"ERROR: Crc32 does not match TempleOS Standard ISO: Good=0x%04x, Bad=0x%04x\r\n", STD_ISO_CRC32, Crc32);
            STALL();
        }
    }
}

void GopSetModeAndPopulateInfo()
{
    EFI_GRAPHICS_OUTPUT_PROTOCOL* Gop;
    Status = gBS->LocateProtocol(&gEfiGraphicsOutputProtocolGuid, NULL,
        (VOID**)&Gop);

    if (EFI_ERROR(Status)) {
        Print(L"ERROR: Could not locate GraphicsOutputProtocol: %r\r\n", Status);
        STALL();
    }

    UINT32 ModeIndex = 0;
    for (UINT64 i = 0; i < Gop->Mode->MaxMode; i++) {
        EFI_GRAPHICS_OUTPUT_MODE_INFORMATION* Info;
        UINTN SizeOfInfo;

        Status = Gop->QueryMode(Gop, i, &SizeOfInfo, &Info);
        if (EFI_ERROR(Status)) {
            continue;
        }

        if (Info->HorizontalResolution == 640 && Info->VerticalResolution == 480) {
            ModeIndex = i;
            break;
        }
    }

    Gop->SetMode(Gop, ModeIndex);
    CUefi* u = (CUefi*)CORE0_32BIT_INIT;
    u->gop_fb_base = Gop->Mode->FrameBufferBase;
    u->gop_fb_size = Gop->Mode->FrameBufferSize;
    u->gop_fb_xres = Gop->Mode->Info->HorizontalResolution;
    u->gop_fb_yres = Gop->Mode->Info->VerticalResolution;
}

void InitMemMaps(UINT64 TotalMemory)
{
    UINT8 Lch = 0;
    if (TotalMemory >= 3000000000) {
        Lch = 0xbf;
    } else if (TotalMemory >= 2000000000) {
        Lch = 0x7f;
    } else {
        return;
    }

    *(UINT8*)(0x7c43) = Lch - 1;
    *(UINT8*)(0x7c8b) = Lch;
    *(UINT8*)(0x7c97) = Lch;

    CMemE820* e820 = (CMemE820*)MEM_E820;

    if (TotalMemory >= 4000000000) {
        e820[E820_LAST_ENTRY].base = 0x100000000;
        e820[E820_LAST_ENTRY].len = TotalMemory - (TotalMemory % GiB) - 0x80000000;
        e820[E820_LAST_ENTRY].type = 0x01;
        *(UINT64*)(MEM_PHYSICAL_SPACE) = TotalMemory - (TotalMemory % GiB) + GiB + 0x40000000;
    }
}

void InitMemVars(UINT64 TotalMemory)
{
    if (TotalMemory >= 4000000000) {
        UINT64 mapped = *(UINT64*)(MEM_PHYSICAL_SPACE) + 0x0100000000;
        UINT64 mem_2meg = mapped / 0x200000;
        UINT64 mem_1gig = mapped / GiB;

        *(UINT64*)(MEM_MAPPED_SPACE) = mapped;
        *(UINT64*)(MEM_2MEG_NUM) = mem_2meg;
        *(UINT64*)(MEM_1GIG_NUM) = mem_1gig;

        UINT64 pml2 = *(UINT64*)(MEM_PML2);

        UINT64 pml3 = pml2 + ROUND_UP(mem_2meg * 8, 0x1000);
        UINT64 pml4 = pml3 + ROUND_UP(mem_1gig * 8, 0x1000);
        UINT64 heap_base = pml4 + 0x1000;

        *(UINT64*)(MEM_PML3) = pml3;
        *(UINT64*)(MEM_PML4) = pml4;
        *(UINT64*)(MEM_HEAP_BASE) = heap_base;
    }
}

void KStart16(UINT64 TotalMemory)
{
    InitMemMaps(TotalMemory);
}

void InitPageTables(UINT64 TotalMemory)
{
    MEMSET((VOID*)SYS_FIXED_AREA, 0, SYS_16MEG_AREA_LIMIT);
    *(UINT64*)(SYS_FIXED_AREA + 0x07c0) = *(UINT64*)MEM_HEAP_BASE;

    // So I herd u liek paeg tabels
    UINT64* entry;
    UINT64 val;

    UINT64 mem_2meg = *(UINT64*)(MEM_2MEG_NUM);
    UINT64 mem_1gig = *(UINT64*)(MEM_1GIG_NUM);

    UINT64 heap_base = *(UINT64*)(MEM_HEAP_BASE);

    UINT64 pml2 = *(UINT64*)(MEM_PML2);
    UINT64 pml3 = *(UINT64*)(MEM_PML3);
    UINT64 pml4 = *(UINT64*)(MEM_PML4);

    // populate PML2
    entry = (UINT64*)pml2;
    val = 0x87;
    entry[0] = 0xe7;
    for (UINT64 i = 1; i < mem_2meg; i++) {
        val += MiB;
        entry[i] = val;
    }

    // populate PML3
    entry = (UINT64*)pml3;
    val = pml2 + 0x07;
    entry[0] = pml2 + 0x27;
    for (UINT64 i = 1; i < mem_1gig; i++) {
        val += 0x1000;
        entry[i] = val;
    }

    // populate PML4
    entry = (UINT64*)pml4;
    entry[0] = pml3 + 0x27;

    UINT32 pags = *(UINT16*)(MEM_E801) << 10;
    pags += 0x100000;
    pags -= heap_base;
    pags >>= MEM_PAG_BITS;

    CMemBlk* blk = (CMemBlk*)heap_base;
    blk->mb_signature = MBS_UNUSED_SIGNATURE_VAL;
    blk->pags = pags;
}

void FallThruToKStart64()
{
    GdtRecord.Limit = 0x107F;
    GdtRecord.Base = 0x0000000000008020ULL;

    IdtRecord.Limit = 0x03FF;
    IdtRecord.Base = 0x0000000000000000ULL;

    asm volatile(
        "lgdt (%0) \n\t"
        "lidt (%1) \n\t"

        "movl $0xC0000101, %%ecx \n\t" // IA32_GS_BASE
        "xorl %%eax, %%eax \n\t"
        "xorl %%edx, %%edx \n\t"
        "wrmsr \n\t"

        "movl $0xC0000100, %%ecx \n\t" // IA32_FS_BASE
        "wrmsr \n\t"

        "movl $0xC0000080, %%ecx \n\t"
        "movl $0x00000500, %%eax \n\t"
        "wrmsr \n\t"

        "movq $0x00000000000006B0, %%rax \n\t"
        "movq %%rax, %%cr4 \n\t"

        "movq 0x00000000000009288, %%rax \n\t"
        "movq %%rax, %%cr3 \n\t"

        "movq $0x0000000080010031, %%rax \n\t"
        "movq %%rax, %%cr0 \n\t"

        "xorq %%rbx, %%rbx \n\t"
        "xorq %%rdx, %%rdx \n\t"
        "xorq %%rbp, %%rbp \n\t"
        "xorq %%r8,  %%r8 \n\t"
        "xorq %%r9,  %%r9 \n\t"
        "xorq %%r10, %%r10 \n\t"
        "xorq %%r11, %%r11 \n\t"
        "xorq %%r12, %%r12 \n\t"
        "xorq %%r13, %%r13 \n\t"
        "xorq %%r14, %%r14 \n\t"
        "xorq %%r15, %%r15 \n\t"

        "movw $0x60, %%ax \n\t"
        "movw %%ax, %%ds \n\t"
        "movw %%ax, %%es \n\t"
        "movw %%ax, %%fs \n\t"
        "movw %%ax, %%gs \n\t"

        "movq $0x0000000080000060, %%rax \n\t"

        "pushq $0x60 \n\t"       // SS
        "pushq $0x97000 \n\t"    // RSP
        "pushq $0x00000046 \n\t" // RFLAGS
        "pushq $0x40 \n\t"       // CS
        "pushq $0x9f75 \n\t"     // KStart64
        "iretq \n\t"
        :
        : "r"(&GdtRecord), "r"(&IdtRecord)
        : "rax", "rbx", "rcx", "rdx", "rsi", "rdi", "memory");
}

void KStart32(UINT64 TotalMemory)
{
    InitMemVars(TotalMemory);
    InitPageTables(TotalMemory);
    FallThruToKStart64();
}

EFI_STATUS
EFIAPI
UefiMain(IN EFI_HANDLE ImageHandle, IN EFI_SYSTEM_TABLE* SystemTable)
{
    UINT64 ActualTotalMemory = GetTotalMemory();
    LoadOperatingSystemFiles();
    DoKernelPatch();
    DoRuntimePatches();

    UINT64 TotalMemory = MaxTotalMemory ? (MaxTotalMemory < ActualTotalMemory ? MaxTotalMemory : ActualTotalMemory) : ActualTotalMemory;

    GopSetModeAndPopulateInfo();
    CUefi* u = (CUefi*)CORE0_32BIT_INIT;
    u->sys_tbl_ptr = (UINT64)SystemTable;
    u->total_mem = ActualTotalMemory;

    ExitUefi(ImageHandle);

    KStart16(TotalMemory);
    KStart32(TotalMemory);

    return EFI_SUCCESS;
}