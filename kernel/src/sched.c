// AeroOS 26R1 — minimal preemptive round-robin scheduler (riscv64 QEMU virt)
//
// Each task gets its own 4 KiB page from the physical-frame allocator.
// Context frame lives 240 bytes below the page top — 30 registers:
//   ra+t0..t6+a0..a7+s0..s11 + sepc + sstatus
// Frame bottom (= sp after push) is saved into task.saved_sp.
//
// Tasks can run in either S-mode (default for kernel workers) or U-mode.
// U-mode tasks enter via sret with sstatus.SPP=0 so subsequent ecalls
// trap into our handler as scause=8 (supervisor env call from U-mode).

#include <stdint.h>
#include <stddef.h>

extern void *aeroos_alloc_page(void);
extern void  aeroos_uart_puts(const char *msg);
extern void  aeroos_uart_putc(char c);

static void u64_dec(uint64_t v);   // fwd decl
int scheduler_create2(void (*entry)(void), int is_usermode);  // fwd decl from scheduler_create

// ---------------------------------------------------------------------------
// Task control block
// ---------------------------------------------------------------------------

#define MAX_TASKS 8
#define CTX_SIZE  240        // 30 regs × 8

// sstatus bits: SPP (bit 8) = previous mode at last trap entry.
// We pre-seed this in the fake frame so sret lands in the right mode.
#define SSTATUS_SPP  0x100    // bit 8
#define SSTATUS_SPIE 0x20     // bit 5 — must be 1 so sret re-enables interrupts

typedef struct task {
    uint64_t saved_sp;
    int      is_usermode;
} task_t;

static task_t tasks[MAX_TASKS];
static int task_count = 0;

// trap.S reads this symbol directly.
task_t *current_task = 0;

// ---------------------------------------------------------------------------
// PMP configuration — give U-mode access to all RAM
// ---------------------------------------------------------------------------

// QEMU virt RAM is 128 MiB at 0x80000000 .. 0x88000000.  We program one
// PMP region matching the entire RAM range with R/W/X for U and S mode.
// pmpaddr encoding for a range of 2^n bytes at base 0x80000000 is:
//   pmpaddr = (base >> 2) | ((n-1) << 5)     (TOR encoding)
// Using NA4 = naturally-aligned 2^n, which is simpler:
//   pmpaddr = (base >> 2)
// But NA4 only matches 2^n starting at base; we want one 128 MiB region.
// 128 MiB = 0x8000000 bytes = 2^27, so NA4:
//   pmpaddr = (0x80000000 >> 2) | ((27 - 2) << 5) = 0x20000000 | 25<<5 = nope...
// Let me just use OFF = 16 MiB granularity with address-0 TOR approach
// or simpler — disable PMP writes since we run on QEMU virt where OpenSBI
// might already have configured things.  Actually let's try with a very
// simple approach:
//   pmpaddr0 = 0x88000000 >> 2 (top of RAM)
//   pmpcfg0  = 0x1F (RWX = bit0/1/2, A = 1)
// No — OpenSBI may have set PMP with different granularity.  Let's skip
// PMP for now and see if U-mode even works without it.  QEMU virt often
// comes up with OpenSBI that leaves PMP disabled for U-mode trap testing.

void scheduler_mp_setup(void) {
    // MSTATUS.MPRV or U-mode PMP — skip for first U-mode test; if U-mode
    // traps fire access-fault scause=1/5, we'll come back here.
}

// ---------------------------------------------------------------------------
// Public API — scheduler core
// ---------------------------------------------------------------------------

void scheduler_init(void) {
    task_count = 0;
    current_task = 0;
    for (int i = 0; i < MAX_TASKS; i++) {
        tasks[i].saved_sp = 0;
        tasks[i].is_usermode = 0;
    }
}

// Push a new S-mode task (kernel worker).
int scheduler_create(void (*entry)(void)) {
    return scheduler_create2(entry, 0 /* is_usermode */);
}

// Push a new task — is_usermode=1 means sret will land in U-mode.
int scheduler_create2(void (*entry)(void), int is_usermode) {
    if (task_count >= MAX_TASKS) return -1;

    uint8_t *page = (uint8_t *)aeroos_alloc_page();
    if (page == 0) return -1;

    uint64_t stack_top = (uint64_t)(page + 4096);
    uint64_t *frame = (uint64_t *)(stack_top - CTX_SIZE);

    // Zero all 30 slots
    for (int i = 0; i < 30; i++) frame[i] = 0;

    frame[28] = (uint64_t)entry;   // sepc
    // frame[29] = sstatus — SPIE must be 1 so subsequent srets re-enable IRQs
    frame[29] = is_usermode ? SSTATUS_SPIE : (SSTATUS_SPP | SSTATUS_SPIE);

    tasks[task_count].saved_sp = (uint64_t)frame;
    tasks[task_count].is_usermode = is_usermode;
    return task_count++;
}

// Round-robin — returns next task's saved frame bottom.
uint64_t scheduler_tick(void) {
    if (current_task == 0) {
        current_task = &tasks[0];
        return tasks[0].saved_sp;
    }
    int idx = (int)(current_task - tasks);
    idx = (idx + 1) % task_count;
    current_task = &tasks[idx];
    return tasks[idx].saved_sp;
}

void scheduler_advance(void) {
    if (current_task == 0 || task_count < 2) return;
    int idx = (int)(current_task - tasks);
    idx = (idx + 1) % task_count;
    current_task = &tasks[idx];
}

int scheduler_count(void) { return task_count; }

int scheduler_current_is_usermode(void) {
    return current_task ? current_task->is_usermode : 0;
}

// ---------------------------------------------------------------------------
// Syscall backend — called from trap.S ecall handler
//   a0 = str ptr, a1 = len → return a0 (bytes written)
// ---------------------------------------------------------------------------

int64_t aeroos_sys_write(const char *s, int64_t n) {
    if (s == 0 || n <= 0) return -1;
    // Walk UART one byte at a time
    const uint8_t *p = (const uint8_t *)s;
    int64_t written = 0;
    for (int64_t i = 0; i < n; i++) {
        aeroos_uart_putc(p[i]);
        written++;
    }
    return written;
}

int64_t aeroos_sys_fork(uint64_t entry) {
    // Fork from U-mode: allocate page + fake frame just like scheduler_create
    // but flag is_usermode=1.  Task number returned.
    return scheduler_create2((void (*)(void))entry, 1);
}

// ---------------------------------------------------------------------------
// Worker demos
// ---------------------------------------------------------------------------

static void busy_delay(uint64_t n) {
    volatile uint64_t x = 0;
    for (uint64_t i = 0; i < n; i++) x = i;
}

void worker_0(void) { while (1) { aeroos_uart_puts("T0: idle\n"); busy_delay(200000); } }
void worker_1(void) { while (1) { aeroos_uart_puts("T1: hi\n");  busy_delay(200000); } }
void worker_2(void) { while (1) { aeroos_uart_puts("T2: hi\n");  busy_delay(200000); } }
void worker_3(void) { while (1) { aeroos_uart_puts("T3: w00t\n"); busy_delay(200000); } }

// ---------------------------------------------------------------------------
// Boot self-test
// ---------------------------------------------------------------------------

int scheduler_demo(void) {
    scheduler_init();
    scheduler_mp_setup();

    int t0 = scheduler_create(worker_0);
    int t1 = scheduler_create(worker_1);
    int t2 = scheduler_create(worker_2);

    extern int aeroos_fork(void (*)(void));
    int t3 = aeroos_fork(worker_3);

    // New: fork a U-mode userapp task using kernel scheduler path directly
    extern void userapp_main(void);
    int t4 = scheduler_create2(userapp_main, 1 /* usermode */);

    current_task = &tasks[0];

    aeroos_uart_puts("sched: init tasks=");
    u64_dec((uint64_t)scheduler_count());
    aeroos_uart_puts(" T0="); u64_dec((uint64_t)t0);
    aeroos_uart_puts(" T1="); u64_dec((uint64_t)t1);
    aeroos_uart_puts(" T2="); u64_dec((uint64_t)t2);
    aeroos_uart_puts(" T3="); u64_dec((uint64_t)t3);
    aeroos_uart_puts(" T4(u)="); u64_dec((uint64_t)t4);
    aeroos_uart_puts("\n");
    return 0;
}

static void u64_dec(uint64_t v) {
    char buf[20]; int i = 0;
    if (v == 0) { aeroos_uart_putc('0'); return; }
    while (v > 0) { buf[i++] = (char)('0'+v%10); v /= 10; }
    while (i > 0) aeroos_uart_putc(buf[--i]);
}
