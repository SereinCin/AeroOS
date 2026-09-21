// Timer driver for AeroOS riscv64 (S-mode), QEMU virt.
//
// OpenSBI runs in M-mode and owns the CLINT.  From S-mode we must NOT
// touch the CLINT MMIO directly: mtimecmp at 0x02004000 is M-mode only,
// and an S-mode load there raises scause=0x05 (load access fault).
//
// Instead the timer is programmed through the legacy SBI call:
//     EID=0 (Set Timer), a0 = ABSOLUTE stime (64-bit)
// and the current counter is read from the S-mode `time` CSR (0xC01).

#include <stdint.h>

extern void aeroos_uart_puts(const char *msg);
extern void aeroos_uart_putc(char c);

// 10 MHz timebase on QEMU virt -> 2_000_000 cycles = 0.2 s.
// Must stay in sync with the interval in trap.S.
#define TIMER_INTERVAL 2000000ULL
#define TIMER_TICK_TARGET 5ULL

// Incremented by trap.S on every supervisor timer interrupt.
// Referenced from assembly (`.extern timer_ticks`), so keep it non-static.
volatile uint64_t timer_ticks = 0;

static inline uint64_t rdtime(void) {
    uint64_t v;
    __asm__ volatile("rdtime %0" : "=r"(v));
    return v;
}

// Legacy SBI: EID=0, a0 = absolute stime.  `.word 0x00000073` is used
// instead of `ecall` to avoid clang integrated-as mangling it.
static inline void sbi_set_timer(uint64_t stime) {
    register uint64_t a0 __asm__("a0") = stime;
    register uint64_t a7 __asm__("a7") = 0;
    __asm__ volatile(".word 0x00000073" :: "r"(a0), "r"(a7) : "memory");
}

uint64_t clint_mtime_read(void) {
    return rdtime();
}

int64_t clint_timer_ticks_read(void) {
    return (int64_t)timer_ticks;
}

int64_t aeroos_get_timer_ticks(void) {
    return (int64_t)timer_ticks;
}

// C helper: enable timer interrupts then wait for at least N ticks.
// Useful from Aero where loop/if/!= syntax is limited.
void aeroos_wait_timer_ticks(int64_t n) {
    int64_t start = (int64_t)timer_ticks;
    while ((int64_t)timer_ticks < start + n) {
        // busy wait — timer interrupt will increment timer_ticks
    }
}

// Arm the next timer interrupt `interval` cycles from now.
void timer_arm(uint64_t interval) {
    sbi_set_timer(rdtime() + interval);
}

// Enable supervisor timer interrupts: arm the timer AND enable bits.
// Without arming there's no future trigger, even if STIE+SIE are both set.
void timer_enable(void) {
    timer_arm(TIMER_INTERVAL);

    uint64_t s;
    __asm__ volatile("csrr %0, sie" : "=r"(s));
    s |= (1ULL << 5);                       // STIE
    __asm__ volatile("csrw sie, %0" :: "r"(s));

    __asm__ volatile("csrr %0, sstatus" : "=r"(s));
    s |= (1ULL << 1);                       // SIE
    __asm__ volatile("csrw sstatus, %0" :: "r"(s));
}

void timer_disable(void) {
    uint64_t s;

    __asm__ volatile("csrr %0, sie" : "=r"(s));
    s &= ~(1ULL << 5);
    __asm__ volatile("csrw sie, %0" :: "r"(s));

    __asm__ volatile("csrr %0, sstatus" : "=r"(s));
    s &= ~(1ULL << 1);
    __asm__ volatile("csrw sstatus, %0" :: "r"(s));
}

static void uart_put_u64(uint64_t v) {
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

// Boot-time self-test: prove an S-mode timer interrupt is taken and that
// the trap handler increments timer_ticks.
void aeroos_timer_demo(void) {
    uint64_t last = 0;

    aeroos_uart_puts("timer: arming S-mode timer interrupt\n");
    timer_arm(TIMER_INTERVAL);
    timer_enable();

    // Loop on `last`, not on `timer_ticks`: reading the volatile counter in
    // the condition races with the 5th interrupt, so the final "tick 5" line
    // could be skipped when the count hits the target mid-iteration.
    while (last < TIMER_TICK_TARGET) {
        uint64_t now = timer_ticks;
        if (now != last) {
            last = now;
            aeroos_uart_puts("tick ");
            uart_put_u64(now);
            aeroos_uart_puts("\n");
        }
    }

    timer_disable();
    aeroos_uart_puts("timer: 5 ticks received\n");
}
