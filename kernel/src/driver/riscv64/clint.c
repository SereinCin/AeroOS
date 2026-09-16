// CLINT driver for RISC-V QEMU virt (S-mode)
//
// MMIO map (verified QEMU virt):
//   mtimecmp base: 0x02004000  (per-hart: + hart_id * 8)
//   mtime:         0x0200BFF8  (shared, 64-bit monotonic counter)
//
// S-mode interrupt enable bits:
//   mstatus.SIE  = 1  (global interrupt enable)
//   sie.STIE     = 1  (supervisor timer interrupt enable)

#include <stdint.h>

#define CLINT_MTIMECMP_BASE 0x02004000ULL
#define CLINT_MTIME         0x0200BFF8ULL

static volatile uint64_t *mtimecmp_for(int hart) {
    return (volatile uint64_t *)(CLINT_MTIMECMP_BASE + (uint64_t)hart * 8);
}

static volatile uint64_t *mtime_reg(void) {
    return (volatile uint64_t *)CLINT_MTIME;
}

// Read current cycle count
uint64_t clint_mtime_read(void) {
    return *mtime_reg();
}

// Set compare value for hart 0 (single-hart kernel for now)
void clint_mtimecmp_set(uint64_t value) {
    *mtimecmp_for(0) = value;
}

// Arm timer to fire in `interval_cycles` cycles from now
void clint_timer_arm(uint64_t interval_cycles) {
    clint_mtimecmp_set(clint_mtime_read() + interval_cycles);
}

// S-mode interrupt enable register (sie)
#define SIE_STIE  (1ULL << 5)   // Supervisor Timer Interrupt Enable
#define SIE_SSIE  (1ULL << 1)   // Supervisor Software Interrupt Enable

static inline uint64_t csr_read_sie(void) {
    uint64_t v;
    __asm__ volatile("csrr %0, sie" : "=r"(v));
    return v;
}

static inline void csr_write_sie(uint64_t v) {
    __asm__ volatile("csrw sie, %0" :: "r"(v));
}

static inline uint64_t csr_read_mstatus(void) {
    uint64_t v;
    __asm__ volatile("csrr %0, mstatus" : "=r"(v));
    return v;
}

static inline void csr_write_mstatus(uint64_t v) {
    __asm__ volatile("csrw mstatus, %0" :: "r"(v));
}

// Supervisor Interrupt Enable bit in mstatus
#define MSTATUS_SIE  (1ULL << 1)

// Enable S-mode timer interrupts (global + per-type)
void clint_timer_enable(void) {
    csr_write_sie(csr_read_sie() | SIE_STIE);
    csr_write_mstatus(csr_read_mstatus() | MSTATUS_SIE);
}

// Disable S-mode timer interrupts
void clint_timer_disable(void) {
    csr_write_mstatus(csr_read_mstatus() & ~MSTATUS_SIE);
}

// Simple busy-wait for `cycles` (used for early boot before interrupts)
void clint_delay_cycles(uint64_t cycles) {
    uint64_t start = clint_mtime_read();
    while ((clint_mtime_read() - start) < cycles) {
        __asm__ volatile("" ::: "memory");
    }
}

// ---- timer_ticks access (trap.S declares .global timer_ticks) ----

uint64_t timer_ticks = 0;  // incremented by trap.S asm handler

int64_t clint_timer_ticks_read(void) {
    int64_t v;
    // asm forces PC-relative addressing (not absolute HI20)
    __asm__ volatile("ld %0, timer_ticks" : "=r"(v));
    return v;
}