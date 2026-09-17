// AeroOS 26R1 — physical page-frame allocator (riscv64, QEMU virt).
//
// RAM layout, confirmed against OpenSBI's boot log:
//   0x80000000  OpenSBI firmware (322 KiB, ends ~0x80051000)
//   0x80200000  kernel image, linked here; ends at _kernel_end
//   0x87e00000  device tree blob passed in a1 (reserved, never handed out)
//   0x88000000  top of QEMU virt's 128 MiB RAM
//
// Frames are 4 KiB.  Free frames are threaded onto a singly-linked list,
// storing the next pointer in the first 8 bytes of each free frame, so the
// allocator keeps no side metadata of its own.

#include <stdint.h>

// Defined by linker.ld, immediately after the boot stack.
extern char _kernel_end[];

#define PAGE_SHIFT   12
#define PAGE_SIZE    (1ULL << PAGE_SHIFT)

#define PHYS_RAM_TOP 0x88000000ULL   // top of QEMU virt's 128 MiB RAM
#define DTB_START    0x87e00000ULL   // DTB (a1) lives here; keep it intact

static uint64_t free_head = 0;       // head of the free list (0 = empty)
static uint64_t frame_total = 0;     // frames under management
static uint64_t frame_free = 0;      // frames currently available

static inline uint64_t align_up(uint64_t v, uint64_t a) {
    return (v + (a - 1)) & ~(a - 1);
}

// Thread every frame in [_kernel_end, DTB_START) onto the free list.
void aeroos_mm_init(void) {
    uint64_t start = align_up((uint64_t)_kernel_end, PAGE_SIZE);

    free_head = 0;
    frame_total = 0;
    frame_free = 0;

    // Walk downwards so the lowest frame ends up at the head of the list.
    uint64_t p = DTB_START;
    while (p >= start + PAGE_SIZE) {
        p -= PAGE_SIZE;
        *(uint64_t *)p = free_head;
        free_head = p;
        frame_total++;
        frame_free++;
    }
}

// Allocate one zeroed 4 KiB frame.  Returns NULL when the pool is empty.
void *aeroos_alloc_page(void) {
    uint64_t p = free_head;
    if (p == 0) {
        return 0;
    }
    free_head = *(uint64_t *)p;
    frame_free--;

    // Zero the frame so callers never see stale RAM contents.
    uint64_t *q = (uint64_t *)p;
    for (uint64_t i = 0; i < PAGE_SIZE / 8; i++) {
        q[i] = 0;
    }
    return (void *)p;
}

// Return a frame previously obtained from aeroos_alloc_page().
void aeroos_free_page(void *page) {
    uint64_t p = (uint64_t)page;
    if (p == 0) {
        return;
    }
    *(uint64_t *)p = free_head;
    free_head = p;
    frame_free++;
}

uint64_t aeroos_mm_total_frames(void) { return frame_total; }
uint64_t aeroos_mm_free_frames(void)  { return frame_free; }

// ---------------------------------------------------------------------------
// Boot self-test
// ---------------------------------------------------------------------------

extern void aeroos_uart_puts(const char *msg);
extern void aeroos_uart_putc(char c);

static void put_u64(uint64_t v) {
    char buf[20];
    int i = 0;

    if (v == 0) {
        aeroos_uart_putc('0');
        return;
    }
    while (v > 0) {
        buf[i++] = (char)('0' + (v % 10));
        v /= 10;
    }
    while (i > 0) {
        aeroos_uart_putc(buf[--i]);
    }
}

static void put_hex(uint64_t v) {
    for (int shift = 60; shift >= 0; shift -= 4) {
        uint64_t nib = (v >> shift) & 0xF;
        aeroos_uart_putc((nib < 10) ? (char)('0' + nib) : (char)('A' + nib - 10));
    }
}

// Prove: init sizes the pool, alloc returns distinct page-aligned frames,
// the frames are real writable RAM, and free() puts a frame back for reuse.
void aeroos_mm_demo(void) {
    aeroos_uart_puts("mm: kernel_end=");
    put_hex((uint64_t)_kernel_end);
    aeroos_uart_puts(" ram_top=");
    put_hex(PHYS_RAM_TOP);
    aeroos_uart_puts("\n");

    aeroos_mm_init();
    aeroos_uart_puts("mm: frames total=");
    put_u64(aeroos_mm_total_frames());
    aeroos_uart_puts(" free=");
    put_u64(aeroos_mm_free_frames());
    aeroos_uart_puts("\n");

    void *a = aeroos_alloc_page();
    void *b = aeroos_alloc_page();
    void *c = aeroos_alloc_page();
    aeroos_uart_puts("mm: alloc a=");
    put_hex((uint64_t)a);
    aeroos_uart_puts(" b=");
    put_hex((uint64_t)b);
    aeroos_uart_puts(" c=");
    put_hex((uint64_t)c);
    aeroos_uart_puts("\n");

    *(volatile uint64_t *)a = 0x1122334455667788ULL;
    *(volatile uint64_t *)c = 0x99AABBCCDDEEFF00ULL;
    int rw_ok = (*(volatile uint64_t *)a == 0x1122334455667788ULL) &&
                (*(volatile uint64_t *)c == 0x99AABBCCDDEEFF00ULL);
    aeroos_uart_puts("mm: readback=");
    aeroos_uart_puts(rw_ok ? "ok" : "FAIL");
    aeroos_uart_puts("\n");

    aeroos_free_page(b);
    void *d = aeroos_alloc_page();
    aeroos_uart_puts("mm: free b, realloc d=");
    put_hex((uint64_t)d);
    aeroos_uart_puts(d == b ? " reused" : " NOT-reused");
    aeroos_uart_puts("\n");

    aeroos_uart_puts("mm: frames free=");
    put_u64(aeroos_mm_free_frames());
    aeroos_uart_puts("\n");
    aeroos_uart_puts("mm: OK\n");
}
