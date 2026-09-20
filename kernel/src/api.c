// AeroOS 26R1 — kernel public API surface.
//
// The kernel exposes a small set of C-callable entry points: fork / yield.
// These are thin wrappers over the scheduler internals and exist so that
// both the demo code and future Aero syscalls call the same stable surface.

#include <stdint.h>

extern int         scheduler_create(void (*entry)(void));
extern void        scheduler_advance(void);
extern uint64_t    clint_mtime_read(void);
extern void        timer_enable(void);

// SBI legacy Set Timer (EID=0, a0 = absolute stime).
static inline void sbi_set_timer(uint64_t stime) {
    register uint64_t a0 __asm__("a0") = stime;
    register uint64_t a7 __asm__("a7") = 0;
    __asm__ volatile(".word 0x00000073" :: "r"(a0), "r"(a7) : "memory");
}

// ---------------------------------------------------------------------------
// API: aeroos_fork(entry)
//   Spawn a new preemptive task running `entry` on a fresh private 4 KiB
//   stack.  Returns the task slot index (>= 0) or -1 on failure.
// ---------------------------------------------------------------------------

int aeroos_fork(void (*entry)(void)) {
    return scheduler_create(entry);
}

// ---------------------------------------------------------------------------
// API: aeroos_yield()
//   Voluntarily hand off the CPU.  Implementation is S-mode-only — we can't
//   directly force a context switch from C code, so we advance the round
//   robin pointer and then busy-wait a fraction of the timer interval so
//   the NEXT timer interrupt pre-empts us into scheduler_tick() and lands
//   on the next task.  When we come back from the interrupt we resume
//   normal execution.
// ---------------------------------------------------------------------------

void aeroos_yield(void) {
    scheduler_advance();

    // Re-arm the timer a short time from now; the busy-wait below won't
    // finish — timer interrupt fires, trap.S saves us, switches to next.
    uint64_t now = clint_mtime_read();
    sbi_set_timer(now + 100000);       // 10 ms
    timer_enable();

    // Busy-wait is interrupted by the timer trap before we reach target.
    uint64_t target = now + 150000;
    while (clint_mtime_read() < target) {
        __asm__ volatile("" ::: "memory");
    }
}
