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

// ---------------------------------------------------------------------------
// Task control block — one uint64_t, held in globals (not per-task heap).
// saved_sp is the frame BOTTOM (= sp value trap.S uses when restoring this
// task's context, i.e. sp after the push of that frame).
// ---------------------------------------------------------------------------

#define MAX_TASKS 8
#define CTX_SIZE 232

typedef struct task {
    uint64_t saved_sp;   // 0 = unused slot
} task_t;

static task_t tasks[MAX_TASKS];
static int task_count = 0;

// trap.S reads this symbol to save/restore the running task's context.
task_t *current_task = 0;

// ---------------------------------------------------------------------------
// UART helpers — same pattern as clint.c / phys.c.
// ---------------------------------------------------------------------------

extern void aeroos_uart_puts(const char *msg);
extern void aeroos_uart_putc(char c);

static void u64_dec(uint64_t v) {
    char buf[20];
    int i = 0;
    if (v == 0) { aeroos_uart_putc('0'); return; }
    while (v > 0) { buf[i++] = (char)('0' + (v % 10)); v /= 10; }
    while (i > 0) aeroos_uart_putc(buf[--i]);
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

// Reset tables; call once at boot BEFORE any scheduler_create.
void scheduler_init(void) {
    task_count = 0;
    current_task = 0;
    for (int i = 0; i < MAX_TASKS; i++) tasks[i].saved_sp = 0;
}

// Push a new task entry point.  Allocates a private 4 KiB stack page and
// prebuilds its 232-byte fake context frame with sepc = entry.
// Returns the slot index on success, -1 on failure.
int scheduler_create(void (*entry)(void)) {
    if (task_count >= MAX_TASKS) return -1;

    uint8_t *page = (uint8_t *)aeroos_alloc_page();
    if (page == 0) return -1;

    uint64_t stack_top = (uint64_t)(page + 4096);
    uint64_t *frame = (uint64_t *)(stack_top - CTX_SIZE);

    // Zero the whole 29-slot frame; only sepc (= entry) matters for boot.
    for (int i = 0; i < 29; i++) frame[i] = 0;
    frame[28] = (uint64_t)entry;

    tasks[task_count].saved_sp = (uint64_t)frame;
    int idx = task_count++;
    return idx;
}

// Round-robin to the next runnable task.  trap.S has already written
// current_task->saved_sp = frame_bottom (= sp after push) before calling us.
// Returns the next task's frame_bottom for trap.S to switch sp to.
//
// First call (current_task is NULL): trap.S hasn't had a current yet, so we
// start at task[0] unconditionally.  The caller MUST set current_task =
// &tasks[0] before enabling timer interrupts — see scheduler_demo().
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

int scheduler_count(void) { return task_count; }

// ---------------------------------------------------------------------------
// Worker demo — each prints its ID every quantum.  Timer interval is
// 0.2 s so we expect ~5 switches / s showing interleaving.
// ---------------------------------------------------------------------------

static void busy_delay(uint64_t n) {
    volatile uint64_t x = 0;
    for (uint64_t i = 0; i < n; i++) x = i;
}

// Idle task (also the "main" context on boot).  main.aero never returns
// to start.S; it calls worker_0 directly and that IS task[0].
void worker_0(void) {
    while (1) {
        aeroos_uart_puts("T0: idle\n");
        busy_delay(200000);
    }
}

void worker_1(void) {
    while (1) {
        aeroos_uart_puts("T1: hi\n");
        busy_delay(200000);
    }
}

void worker_2(void) {
    while (1) {
        aeroos_uart_puts("T2: hi\n");
        busy_delay(200000);
    }
}

// ---------------------------------------------------------------------------
// Boot self-test — run once from main.aero to set up the task table, then
// main.aero calls worker_0() directly to enter task[0].
// ---------------------------------------------------------------------------

int scheduler_demo(void) {
    scheduler_init();

    int t0 = scheduler_create(worker_0);
    int t1 = scheduler_create(worker_1);
    int t2 = scheduler_create(worker_2);

    // Now that all tasks are registered, point current at task[0].  When
    // the first timer trap fires, trap.S writes frame_bottom into
    // current_task->saved_sp (= tasks[0]), advances to task[1], and we go.
    current_task = &tasks[0];

    aeroos_uart_puts("sched: init tasks=");
    u64_dec(scheduler_count());
    aeroos_uart_puts(" T0 idx=");
    u64_dec(t0);
    aeroos_uart_puts(" T1 idx=");
    u64_dec(t1);
    aeroos_uart_puts(" T2 idx=");
    u64_dec(t2);
    aeroos_uart_puts("\n");

    return 0;
}
