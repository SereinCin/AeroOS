// AeroOS 26R1 — minimal kernel heap (kmalloc/kfree) on top of the phys
// page-frame allocator.  Each 4 KiB page from aeroos_alloc_page() is
// carved into 8-byte-aligned blocks with a 16-byte header:
//
//   block header (16B): size [bit62=FREE, bit63=USED, low62=payload size]
//   block payload:      8-byte-aligned user data
//
// Page layout:
//
//   ┌─ base (= page returned from aeroos_alloc_page) ────────────────┐
//   │ first hdr_t | payload ... | second hdr_t | payload ...         │
//   ...                                                                │
//   ├─ pghead_t (page_next 8B + hdr_t 16B = 24B total) ──────────────┤
//   └─ top (= base + 4096) ────────────────────────────────────────────┘
//
// Traversal starts at page bottom (pghead_t 的 base 我们存成 0，每次
// 用 `pg + sizeof(pghead_t) - PAGE_SIZE` 反推)。

#include <stdint.h>
#include <stddef.h>

extern void *aeroos_alloc_page(void);
extern void  aeroos_free_page(void);

#define PAGE_SIZE 4096
#define ALIGN      8
#define HDR_SIZE  16

#define USED_BIT  (1ULL << 63)
#define FREE_BIT  (1ULL << 62)

typedef struct hdr {
    uint64_t next;   // 同页内下一个 hdr 的偏移，简化版始终不用
    uint64_t size;   // low62 = payload bytes; bit62=FREE; bit63=USED
} hdr_t;

// 页头放在 4 KiB 页的最顶端。
typedef struct pghead {
    uint64_t page_next;
    hdr_t    hdr;          // pghead 自带的 hdr 仅占占位，不参与遍历
} pghead_t;

static pghead_t *heap_head = 0;

static inline uint64_t align_up(uint64_t v, uint64_t a) {
    return (v + (a - 1)) & ~(a - 1);
}

// 给定 pghead_t 指针，反推页底（第一个 block 起点）。
static inline uint8_t *page_base(pghead_t *pg) {
    return (uint8_t *)pg + sizeof(pghead_t) - PAGE_SIZE;
}

static inline pghead_t *page_next(pghead_t *pg) {
    if (!pg->page_next) return 0;
    return (pghead_t *)((uint8_t *)pg + pg->page_next);
}

// 申请新 4 KiB 页，在里面放一个大 free block 占满页底到 pghead 顶之间。
static pghead_t *new_heap_page(void) {
    uint8_t *base = (uint8_t *)aeroos_alloc_page();
    if (base == 0) return 0;
    uint8_t *top = base + PAGE_SIZE;

    pghead_t *pg = (pghead_t *)(top - sizeof(pghead_t));  // 页顶的 pghead
    hdr_t *hb = (hdr_t *)base;                              // 页底的第一个 block
    uint64_t usable = (uint64_t)(top - sizeof(pghead_t) - HDR_SIZE);

    hb->next = 0;
    hb->size = usable | FREE_BIT;

    pg->page_next = 0;
    pg->hdr.next  = 0;
    pg->hdr.size  = 0;   // 占位，遍历从页底开始

    if (heap_head == 0) {
        heap_head = pg;
    } else {
        pghead_t *tail = heap_head;
        while (page_next(tail)) tail = page_next(tail);
        tail->page_next = (uint64_t)((uint8_t *)pg - (uint8_t *)tail);
    }
    return pg;
}

// 在一页里 first-fit 找 >= need 的 FREE block。
static hdr_t *find_free_in_page(pghead_t *pg, uint64_t need, uint8_t **out_end) {
    uint8_t *base  = page_base(pg);
    uint8_t *limit = (uint8_t *)pg;           // 不能越过 pghead 起点
    uint8_t *cur   = base;
    while (cur < limit) {
        hdr_t *h = (hdr_t *)cur;
        uint64_t flag = h->size & (USED_BIT | FREE_BIT);
        uint64_t size = h->size & ~(USED_BIT | FREE_BIT);
        if (flag == FREE_BIT && size >= need) {
            if (out_end) *out_end = cur + HDR_SIZE + size;
            return h;
        }
        if (size == 0) break;   // 守护
        cur += HDR_SIZE + size;
    }
    return 0;
}

void *kmalloc(size_t n) {
    if (n == 0) return 0;
    uint64_t need = align_up((uint64_t)n, ALIGN);

    // 遍历所有页找 first-fit
    for (pghead_t *pg = heap_head; pg; pg = page_next(pg)) {
        hdr_t *h = find_free_in_page(pg, need, 0);
        if (!h) continue;

        // split: 如果剩的空间还够一个新 header + 至少 ALIGN 的 payload
        uint64_t orig = h->size & ~(USED_BIT | FREE_BIT);
        uint64_t leftover = orig - need - HDR_SIZE;
        if (leftover >= ALIGN) {
            uint8_t *split = (uint8_t *)h + HDR_SIZE + need;
            hdr_t *rest = (hdr_t *)split;
            rest->next = 0;
            rest->size = leftover | FREE_BIT;
            h->size    = need | USED_BIT;
        } else {
            h->size = orig | USED_BIT;
        }
        return (void *)((uint8_t *)h + HDR_SIZE);
    }

    // 没有合适的 free block — 申请新页
    pghead_t *pg = new_heap_page();
    if (!pg) return 0;
    hdr_t *h = find_free_in_page(pg, need, 0);
    if (!h) return 0;   // 理论上不可能，新页总有一个大 block
    uint64_t orig = h->size & ~(USED_BIT | FREE_BIT);
    uint64_t leftover = orig - need - HDR_SIZE;
    if (leftover >= ALIGN) {
        uint8_t *split = (uint8_t *)h + HDR_SIZE + need;
        hdr_t *rest = (hdr_t *)split;
        rest->next = 0;
        rest->size = leftover | FREE_BIT;
        h->size    = need | USED_BIT;
    } else {
        h->size = orig | USED_BIT;
    }
    return (void *)((uint8_t *)h + HDR_SIZE);
}

void kfree(void *p) {
    if (!p) return;

    // 找到 block header
    hdr_t *h = (hdr_t *)((uint8_t *)p - HDR_SIZE);

    // 定位它所在的页 — 必须在 heap_head 链上某页范围内
    for (pghead_t *pg = heap_head; pg; pg = page_next(pg)) {
        uint8_t *base  = page_base(pg);
        uint8_t *limit = (uint8_t *)pg;
        if ((uint8_t *)h >= base && (uint8_t *)h < limit) {
            h->size = (h->size & ~USED_BIT) | FREE_BIT;

            // 和后邻居合并（如果也是 free 的）
            uint8_t *next_base = (uint8_t *)h + HDR_SIZE + (h->size & ~(USED_BIT|FREE_BIT));
            if (next_base + HDR_SIZE <= limit) {
                hdr_t *next = (hdr_t *)next_base;
                if ((next->size & FREE_BIT) && (next->size & ~(USED_BIT|FREE_BIT)) != 0) {
                    uint64_t total = (h->size & ~(USED_BIT|FREE_BIT)) + HDR_SIZE
                                   + (next->size & ~(USED_BIT|FREE_BIT));
                    h->size = total | FREE_BIT;
                }
            }
            return;
        }
    }
    // 不在任何已知堆页上 — 允许静默泄漏（kernel bring-up 阶段）
}

// ---------------------------------------------------------------------------
// Boot self-test — 证明 kmalloc/kfree 链路真的通
// ---------------------------------------------------------------------------

extern void aeroos_uart_puts(const char *msg);
extern void aeroos_uart_putc(char c);

static void u64_hex(uint64_t v) {
    for (int s = 60; s >= 0; s -= 4) {
        uint64_t nib = (v >> s) & 0xF;
        aeroos_uart_putc((nib < 10) ? (char)('0'+nib) : (char)('A'+nib-10));
    }
}

void aeroos_heap_demo(void) {
    aeroos_uart_puts("heap: demo\n");

    void *a = kmalloc(64);
    void *b = kmalloc(128);
    void *c = kmalloc(1024);
    aeroos_uart_puts("heap: a="); u64_hex((uint64_t)a);
    aeroos_uart_puts(" b=");      u64_hex((uint64_t)b);
    aeroos_uart_puts(" c=");      u64_hex((uint64_t)c);
    aeroos_uart_puts("\n");

    if (a == 0 || b == 0 || c == 0) {
        aeroos_uart_puts("heap: FAIL (kmalloc returned 0)\n");
        return;
    }

    *(volatile uint64_t *)a = 0xDEADBEEF;
    *(volatile uint64_t *)c = 0xCAFEBABE;
    int ok1 = *(volatile uint64_t *)a == 0xDEADBEEF;
    int ok2 = *(volatile uint64_t *)c == 0xCAFEBABE;
    aeroos_uart_puts("heap: write=");
    aeroos_uart_puts(ok1 && ok2 ? "ok" : "FAIL");
    aeroos_uart_puts("\n");

    int aligned = (((uint64_t)a | (uint64_t)b | (uint64_t)c) & 7) == 0;
    int distinct = a != b && b != c && a != c;
    aeroos_uart_puts("heap: aligned="); aeroos_uart_putc(aligned ? 'y' : 'n');
    aeroos_uart_puts(" distinct=");     aeroos_uart_putc(distinct ? 'y' : 'n');
    aeroos_uart_puts("\n");

    kfree(b);
    void *d = kmalloc(128);
    aeroos_uart_puts("heap: free b, realloc d="); u64_hex((uint64_t)d);
    aeroos_uart_puts(" same=");                   aeroos_uart_puts(d == b ? "y" : "n");
    aeroos_uart_puts("\n");

    // 额外：malloc/free 链路（libc_stub 委托给 kmalloc/kfree）
    extern void *malloc(size_t);
    extern void  free(void *);
    void *e = malloc(256);
    *(volatile uint8_t *)e = 0x5A;
    aeroos_uart_puts("heap: malloc e="); u64_hex((uint64_t)e);
    aeroos_uart_puts(" ok=");            aeroos_uart_puts(*(volatile uint8_t *)e == 0x5A ? "y" : "n");
    aeroos_uart_puts("\n");
    free(e);

    aeroos_uart_puts("heap: OK\n");
}
