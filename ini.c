BOOLEAN ParseIniKeyValue(UINT64 base, UINT64 len, UINT8* key, UINT8* value, UINT64* pos)
{
    MEMSET(key, 0, 256);
    MEMSET(value, 0, 256);

    UINT64 i = *pos;
    if (i >= len) {
        return FALSE;
    }

    UINT8* p = (UINT8*)base;
    UINT64 state = 0;
    UINT64 ki = 0;
    UINT64 vi = 0;

    while (i < len) {
        UINT8 ch = p[i++];
        switch (state) {
        case 4: // IN_VAL
            switch (ch) {
            case ' ':
            case '\r':
            case '\t':
            case '\n':
                *pos = i;
                return ki > 0;
            default:
                value[vi++] = ch;
                break;
            }
            break;

        case 3: // BEFORE_VAL
            switch (ch) {
            case ' ':
            case '\r':
            case '\t':
            case '\n':
                break;
            default:
                i--;
                state = 4;
                break;
            }
            break;

        case 2: // BEFORE_SEP
            switch (ch) {
            case '=':
                state = 3;
                break;
            case ' ':
            case '\r':
            case '\t':
            case '\n':
                break;
            default:
                // error in parser
                return FALSE;
            }
            break;

        case 1: // IN_KEY
            switch (ch) {
            case '=':
            case ' ':
            case '\r':
            case '\t':
            case '\n':
                i--;
                state = 2;
                break;
            default:
                key[ki++] = ch;
                break;
            }
            break;

        case 0: // BEFORE_KEY
            switch (ch) {
            case ' ':
            case '\r':
            case '\t':
            case '\n':
                break;
            default:
                i--;
                state = 1;
                break;
            }
            break;
        }
    }

    *pos = i;
    return ki > 0;
}

BOOLEAN ParseIniU64(CHAR8* buf, UINT64* u64)
{
    return !EFI_ERROR(AsciiStrDecimalToUint64S(buf, NULL, u64));
}