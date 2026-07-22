#define BGRA_BLACK 0xff000000
#define BGRA_WHITE 0xffffffff

U0 UefiPutChar(I64 ch)
{
    I64 row, col;
    CTextGlbls* t = 0xc388;

    U64* gop_addr = CORE0_32BIT_INIT;
    U32* pixels = gop_addr[0];

    if (!(t->raw_flags & RWF_SHOW_DOLLAR)) {
        if (ch == '\d') {
            if (t->raw_flags & RWF_IN_DOLLAR) {
                t->raw_flags &= ~RWF_IN_DOLLAR;
                if (!(t->raw_flags & RWF_LAST_DOLLAR)) {
                    t->raw_flags &= ~RWF_LAST_DOLLAR;
                    return;
                }
            } else {
                t->raw_flags |= RWF_IN_DOLLAR | RWF_LAST_DOLLAR;
                return;
            }
        }
        t->raw_flags &= ~RWF_LAST_DOLLAR;
        if (t->raw_flags & RWF_IN_DOLLAR)
            return;
    }
    if (ch == '\t') {
        UefiPutChar(CH_SPACE);
        while (t->raw_col & 7)
            UefiPutChar(CH_SPACE);
    } else if (ch == CH_BACKSPACE) {
        t->raw_col--;
        UefiPutChar(CH_SPACE);
        t->raw_col--;
    } else if (ch == '\n') {
        UefiPutChar(CH_SPACE);
        while (t->raw_col % TEXT_COLS)
            UefiPutChar(CH_SPACE);

    } else if (ch >= CH_SHIFT_SPACE) {
        row = t->raw_col / TEXT_COLS % TEXT_ROWS;
        col = t->raw_col % TEXT_COLS;

        if (t->raw_flags & RWF_SCROLL && t->raw_col && !row && !col) {
            // **** Scroll cached image ****
            MemCpy(pixels, pixels(U64) + 0x5000, 0x127000);
            MemSetU32(pixels(U64) + 0x127000, BGRA_BLACK, 0x1400);
            t->raw_col -= TEXT_COLS;
            row = TEXT_ROWS - 1;
        }

        I64 cx, cy; // ch x, y pos
        I64 px, py; // plot (FrameBuffer) x, y pos
        U32 color;

        U64* font_addr = 0xc3b0;
        U64 ch_offset = font_addr[0];
        ch_offset += (ch * 8);
        U8* ch_row = ch_offset;

        // **** Draw character ****
        for (cy = 0; cy < 8; cy++) {
            for (cx = 0; cx < 8; cx++) {

                color = BGRA_BLACK;
                if ((ch_row[cy] >> cx) & 1) {
                    color = BGRA_WHITE;
                }

                py = (row * 8) + cy;
                px = (col * 8) + cx;

                pixels[(py * GR_WIDTH) + px] = color;
            }
        }

        t->raw_col++;
    }
}

MemSet(&RawPutChar, 0x90, sizeof(RawPutChar));
MemCpy(&RawPutChar, &UefiPutChar, sizeof(UefiPutChar));

MemSetI64(&RawPutChar + 0x0077 + 0x02, &RawPutChar, 1);
*(&RawPutChar + 0x0077 + 0x0a)(U16*) = 0xd3ff;
MemSetI64(&RawPutChar + 0x0090 + 0x02, &RawPutChar, 1);
*(&RawPutChar + 0x0090 + 0x0a)(U16*) = 0xd3ff;
MemSetI64(&RawPutChar + 0x00a9 + 0x02, &RawPutChar, 1);
*(&RawPutChar + 0x00a9 + 0x0a)(U16*) = 0xd3ff;
MemSetI64(&RawPutChar + 0x00c5 + 0x02, &RawPutChar, 1);
*(&RawPutChar + 0x00c5 + 0x0a)(U16*) = 0xd3ff;
MemSetI64(&RawPutChar + 0x00eb + 0x02, &RawPutChar, 1);
*(&RawPutChar + 0x00eb + 0x0a)(U16*) = 0xd3ff;

PatchCallRel32(&RawPutChar + 0x015b, &MemCpy);
PatchCallRel32(&RawPutChar + 0x0173, &MemSetU32);

FileWrite("B:/UefiPutChar.BIN", &RawPutChar, sizeof(RawPutChar));
QMonSave("B:/UefiPutChar.BIN");
