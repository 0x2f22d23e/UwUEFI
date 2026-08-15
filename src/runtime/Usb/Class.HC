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
#define EPx_RING_TRBS 8

#define MAX_SLOTS_WANT 32
#define MAX_SCRATCHPAD 32

#define QEMU_XHCI_BAR0 0xd0000000
#define XHCI_PCI usb.d.u8[2], usb.d.u8[1], usb.d.u8[0]
#define XHCI_WAIT_INTERVAL 8000000

#define USB_STR 128
#define HUB_MAX_PORTS 32

#define USB_TYPE_DEFAULT 0
#define USB_TYPE_KEYBOARD 1
#define USB_TYPE_MOUSE 2
#define USB_TYPE_HUB 3

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

class CUsbHubDesc {
    U8 bLength;
    U8 bDescriptorType;
    U8 bNumPorts;
    U16 wHubCharacteristics;
};

U32 SLOT_2_TT_TIME(U32 x)
{
    return (((x) & 0x3) << 16);
}

U32 HUB_TTT_GET(U32 x)
{
    return (((x) >> 5) & 0x3);
}

class CUsbDevice {
    U8 type;
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
    CXhciRing kb;
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

class CUsbHub : CUsbDevice {
    CXhciRing hub;
    CUsbHubDesc hdesc;
    U8* report;
    U8 last_report[8];
    I64 timestamp;
    Bool enabled;
    CUsbDevice* dev[HUB_MAX_PORTS];
    U8 ccs_state[HUB_MAX_PORTS];
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
    Bool running;
    CUsbKeyboard* kb;
    CUsbMouse* ms;
    CUsbHub* root;
    Bool debug;
} usb;
