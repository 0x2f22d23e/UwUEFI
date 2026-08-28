#define DW_IC_CON 0x00
#define DW_IC_TAR 0x04
#define DW_IC_DATA_CMD 0x10
#define DW_IC_FS_SCL_HCNT 0x1c
#define DW_IC_FS_SCL_LCNT 0x20
#define DW_IC_CLR_INTR 0x40
#define DW_IC_CLR_TX_ABRT 0x54
#define DW_IC_ENABLE 0x6c
#define DW_IC_STATUS 0x70
#define DW_IC_TXFLR 0x74
#define DW_IC_RXFLR 0x78
#define DW_IC_SDA_HOLD 0x7c
#define DW_IC_TX_ABRT_SOURCE 0x80

#define I2C_RESETS 0x204
#define I2C_CLOCK_GATE 0x238

#define I2C_PCI i2c.d.u8[2], i2c.d.u8[1], i2c.d.u8[0]

#define I2C_TYPE_DEFAULT 0
#define I2C_TYPE_MOUSE 1

class CI2cDevice {
    U8 type;
    U8 address;
};

class CI2cMouse : CI2cDevice {
    U8 report[16];
    U8 last_report[16];
};

class CI2c {
    I64 d;
    U64 mmio_base;
    Bool running;
    CI2cMouse* ms;
    Bool debug;
} i2c;
