#define CAP_CAPLENGTH 0x00
#define CAP_HCSPARAMS1 0x04
#define CAP_HCSPARAMS2 0x08
#define CAP_HCCPARAMS1 0x10
#define CAP_DBOFF 0x14
#define CAP_RTSOFF 0x18

#define OP_USBCMD 0x00
#define OP_USBSTS 0x04
#define OP_DCBAAP 0x30
#define OP_CONFIG 0x38
#define OP_CRCR 0x18
#define OP_PORTSC_BASE 0x400

#define USBCMD_RUN (1 << 0)
#define USBCMD_HCRST (1 << 1)
#define USBSTS_HCH (1 << 0)
#define USBSTS_CNR (1 << 11)
#define PORTSC_CCS (1 << 0)
#define PORTSC_PP (1 << 9)

#define RT_IR0_ERSTSZ 0x28
#define RT_IR0_ERSTBA 0x30
#define RT_IR0_ERDP 0x38

#define CMD_RING_TRBS 32
#define EVT_RING_TRBS 32

#define EP0_RING_TRBS 8
#define KBD_RING_TRBS 8
#define MS_RING_TRBS 8

#define MAX_SLOTS_WANT 8
#define MAX_SCRATCHPAD 32

#define QEMU_XHCI_BAR0 0xd0000000
#define XHCI_PCI usb.d.u8[2], usb.d.u8[1], usb.d.u8[0]
#define XHCI_WAIT_INTERVAL 8000000

#define USB_STR 128

U64 CALLOC_64(I64 size)
{
    return CAllocAligned(size, 64, adam_task->code_heap);
}
U64 CALLOC_4K(I64 size)
{
    return CAllocAligned(size, 4096, adam_task->code_heap);
}
U64 CALLOC_64K(I64 size)
{
    return CAllocAligned(size, 65536, adam_task->code_heap);
}

U32 MMIO_READ_U32(U64 addr)
{
    return *(addr)(U32*);
}
U0 MMIO_WRITE_U32(U64 addr, U32 v)
{
    *(addr)(U32*) = v;
}
U0 MMIO_WRITE_U64(U64 addr, U64 v)
{
    *(addr)(U64*) = v;
}

class CXhciTrb {
    U32 d0;
    U32 d1;
    U32 d2;
    U32 d3;
};

class CXhciRing {
    CXhciTrb* ring;
    U32 q;
    U32 cycle;
};

class CUsbDeviceDesc {
    U8 bLength;
    U8 bDescriptorType;
    U16 bcdUSB;
    U8 bDeviceClass;
    U8 bDeviceSubClass;
    U8 bDeviceProtocol;
    U8 bMaxPacketSize0;
    U16 idVendor;
    U16 idProduct;
    U16 bcdDevice;
    U8 iManufacturer;
    U8 iProduct;
    U8 iSerialNumber;
    U8 bNumConfigurations;
};

class CUsbInterfaceDesc {
    U8 bLength;
    U8 bDescriptorType;
    U8 bInterfaceNumber;
    U8 bAlternateSetting;
    U8 bNumEndpoints;
    U8 bInterfaceClass;
    U8 bInterfaceSubClass;
    U8 bInterfaceProtocol;
    U8 iInterface;
};

class CUsbDevice {
    U32 port;
    U32 slot_id;
    CXhciRing ep0;
    U8* input_ctx;
    U8* dev_ctx_out;
    U8* ctrl_buf;
    CUsbDeviceDesc desc;
    CUsbInterfaceDesc iface;
    U16 lang_id;
    U8 mfr[USB_STR];
    U8 prod[USB_STR];
};

class CUsbKeyboard : CUsbDevice {
    CXhciRing kbd;
    U8* report;
    U8 last_report[8];
    I64 next_repeat;
    I64 timestamp;
};

class CUsbMouse : CUsbDevice {
    CXhciRing ms;
    U8* report;
    U8 last_report[8];
    I64 timestamp;
};

class CUsb {
    I64 d;
    U64 mmio_base;
    U64 op_base;
    U64 rt_base;
    U64 db_base;
    U32 max_slots;
    U32 max_ports;
    U32 max_intrs;
    U32 context_size;
    CXhciRing cmd;
    CXhciRing evt;
    U64* erst;
    U64* dcbaa;
    U64* scratch_ptrs;
    U8* scratch_buf;
    U8 ccs_state[64];
    Bool running;
    CUsbKeyboard* kb;
    CUsbMouse* ms;
    CUsbDevice* dev[32];
} usb;
