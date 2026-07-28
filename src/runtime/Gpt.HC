class CGptEntry {
    U64 type_lo;
    U64 type_hi;
    U64 id_lo;
    U64 id_hi;
    U64 lba_start;
    U64 lba_end;
    U64 flags;
    U16 wname[36];
};

class CGptHeader {
    U8 signature[8];
    U32 revision;
    U32 hdr_size;
    U32 crc32;
    U8 rsvd[4];
    U64 this_hdr;
    U64 alt_hdr;
    U64 first_lba;
    U64 last_lba;
    U64 diskid_lo;
    U64 diskid_hi;
    U64 pe_lba;
    U32 pe_cnt;
    U32 pe_size;
    U32 pe_crc32;
};

U0 GptType(U8* guid)
{
    if (!StrCmp(guid, "c12a7328-f81f-11d2-ba4b-00a0c93ec93b")) {
        return "EFI System";
    }
    if (!StrCmp(guid, "4f68bce3-e8cd-4db1-96e7-fbcaf984b709")) {
        return "Linux Root";
    }
    if (!StrCmp(guid, "933ac7e1-2eb4-4f13-b844-0e14e2aef915")) {
        return "Linux Home";
    }
    if (!StrCmp(guid, "3b8f8425-20e0-4f3b-907f-1a25a76f98e8")) {
        return "Linux Server Data";
    }
    if (!StrCmp(guid, "0fc63daf-8483-4772-8e79-3d69d8477de4")) {
        return "Linux Other Data";
    }
    if (!StrCmp(guid, "0657fd6d-a4ab-43c4-84e5-0933c84b4f4f")) {
        return "Swap";
    }
    if (!StrCmp(guid, "e3c9e316-0b5c-4db8-817d-f92df00215ae")) {
        return "Microsoft Reserved";
    }
    if (!StrCmp(guid, "ebd0a0a2-b9e5-4433-87c0-68b6b72699c7")) {
        return "Microsoft Basic Data";
    }
    if (!StrCmp(guid, "de94bba4-06d1-4d40-a16a-bfd50179d6ac")) {
        return "Windows Recovery Environment";
    }
    return "Unknown";
}

Bool IsGpt(CMasterBoot* mb)
{
    return (mb->signature == 0xaa55) && (mb->p[0].type == 0xee);
}

U0 MakeGuid(U8* dst, U64 e)
{
    MemSet(dst, 0, 38);
    StrPrint(dst, "%08x-%04x-%04x-%04x-", *e(U32*), e(U16*)[2], e(U16*)[3], EndianU16(e(U16*)[4]));
    I64 i;
    for (i = 0; i < 6; i++) {
        StrPrint(dst + StrLen(dst), "%02x", e(U8*)[0x0a + i]);
    }
}
