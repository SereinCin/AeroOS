// AeroOS 26R1 — minimal preemptive round-robin scheduler (riscv64 QEMU virt).
//
// Each task gets its own 4 KiB page from the physical-frame allocator, which
// sits at the top of the task's stack.  A 232-byte context frame
// (ra + t0..t6 + a0..a7 + s0..s11 + sepc = 29 registers) lives 232 bytes
// below the page top; trap.S loads this as sp and restores from it.
//
// On every timer interrupt the running task's frame is saved, round-robin
// advances to the next, and we sret into that task's saved sepc.

#include <stdint.h>

extern void *aeroos_alloc_page(void);
extern void  aeroos_uart_puts(const char *msg);
extern void  aeroos_uart_putc(char c);

static void u64_dec(uint64_t v);   // fwd declaration for scheduler_demo

// ---------------------------------------------------------------------------
// Task control block — one uint64_t (frame bottom), held in globals.
// ---------------------------------------------------------------------------

#define MAX_TASKS 8
#define CTX_SIZE  232

typedef struct task {
    uint64_t saved_sp;
} task_t;

static task_t tasks[MAX_TASKS];
static int task_count = 0;

// trap.S reads this symbol to save/restore the running task's context.
task_t *current_task = 0;

// ---------------------------------------------------------------------------
// Public API — scheduler core
// ---------------------------------------------------------------------------

void scheduler_init(void) {
    task_count = 0;
    current_task = 0;
    for (int i = 0; i < MAX_TASKS; i++) tasks[i].saved_sp = 0;
}

// Push a new task entry point.  Allocates a private 4 KiB stack page and
// prebuilds its 232-byte fake context frame (sepc = entry, other regs 0).
// Returns slot index on success, -1 on failure.
int scheduler_create(void (*entry)(void)) {
    if (task_count >= MAX_TASKS) return -1;

    uint8_t *page = (uint8_t *)aeroos_alloc_page();
    if (page == 0) return -1;

    uint64_t stack_top = (uint64_t)(page + 4096);
    uint64_t *frame = (uint64_t *)(stack_top - CTX_SIZE);

    for (int i = 0; i < 29; i++) frame[i] = 0;
    frame[28] = (uint64_t)entry;   // sepc

    tasks[task_count].saved_sp = (uint64_t)frame;
    int idx = task_count++;
    return idx;
}

// Round-robin to the next runnable task.  trap.S has already written
// current_task->saved_sp = frame_bottom (= sp after push) before calling.
// Returns the next task's frame_bottom for trap.S to switch sp to.
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

// Advance current_task pointer without actually switching frames.  Used by
// aeroos_yield() to "hand off" via the NEXT timer interrupt that fires.
void scheduler_advance(void) {
    if (current_task == 0 || task_count < 2) return;
    int idx = (int)(current_task - tasks);
    idx = (idx + 1) % task_count;
    current_task = &tasks[idx];
}

int scheduler_count(void) { return task_count; }

// ---------------------------------------------------------------------------
// Worker demo — each prints its ID every quantum.  Timer interval is
// 0.2 s so we see ~5 switches / s per worker.
// ---------------------------------------------------------------------------

extern void aeroos_uart_puts(const char *msg);

static void busy_delay(uint64_t n) {
    volatile uint64_t x = 0;
    for (uint64_t i = 0; i < n; i++) x = i;
}

void worker_0(void) {
    while (1) { aeroos_uart_puts("T0: idle\n"); busy_delay(200000); }
}
void worker_1(void) {
    while (1) { aeroos_uart_puts("T1: hi\n");  busy_delay(200000); }
}
void worker_2(void) {
    while (1) { aeroos_uart_puts("T2: hi\n");  busy_delay(200000); }
}
void worker_3(void) {
    while (1) { aeroos_uart_puts("T3: w00t\n"); busy_delay(200000); }
}

// ---------------------------------------------------------------------------
// Boot self-test — builds the task table; current_task is arm'd AFTER
// the table exists so the first timer trap saves task[0] correctly.
// ---------------------------------------------------------------------------

int scheduler_demo(void) {
    scheduler_init();

    int t0 = scheduler_create(worker_0);
    int t1 = scheduler_create(worker_1);
    int t2 = scheduler_create(worker_2);

    // Fourth task created via the PUBLIC aeroos_fork() API to prove the
    // high-level path works (calls scheduler_create internally).
    extern int aeroos_fork(void (*entry)(void));
    int t3 = aeroos_fork(worker_3);

    current_task = &tasks[0];

    aeroos_uart_puts("sched: init tasks=");
    u64_dec((uint64_t)scheduler_count());
    aeroos_uart_puts(" T0="); u64_dec((uint64_t)t0);
    aeroos_uart_puts(" T1="); u64_dec((uint64_t)t1);
    aeroos_uart_puts(" T2="); u64_dec((uint64_t)t2);
    aeroos_uart_puts(" T3="); u64_dec((uint64_t)t3);
    aeroos_uart_puts("\n");

    return 0;
}

static void u64_dec(uint64_t v) {
    char buf[20]; int i = 0;
    if (v == 0) { aeroos_uart_putc('0'); return; }
    while (v > 0) { buf[i++] = (char)('0'+v%10); v /= 10; }
    while (i > 0) aeroos_uart_putc(buf[--i]);
}
