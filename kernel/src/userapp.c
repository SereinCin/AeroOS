// AeroOS 26R1 — first U-mode user application
//
// This runs in U-mode.  It has NO direct access to kernel functions —
// every service comes through a supervisor ecall (scause=8 when it
// lands in trap.S).  We provide three syscall wrappers via inline asm:
//   sys_write(str, len)  a7=1
//   sys_yield()          a7=2
//   sys_exit()           a7=4
//
// The entry point is userapp_main — scheduler_create2 flags this as
// U-mode (sstatus.SPP=0 in the fake frame) so the first sret drops us
// from S to U.

#include <stdint.h>

// Inline-asm sys_write(a0=str, a1=len).  Returns a0 = bytes written.
static inline int64_t sys_write(const char *s, int64_t n) {
    register int64_t a0 __asm__("a0") = (int64_t)s;
    register int64_t a1 __asm__("a1") = n;
    register int64_t a7 __asm__("a7") = 1;          // SYS_write
    __asm__ volatile(
        ".word 0x00000073"                          // ecall
        : "+r"(a0)
        : "r"(a1), "r"(a7)
        : "memory"
    );
    return a0;
}

static inline void sys_yield(void) {
    register int64_t a7 __asm__("a7") = 2;          // SYS_yield
    __asm__ volatile(
        ".word 0x00000073"
        :: "r"(a7)
        : "memory"
    );
}

static inline void sys_exit(void) {
    register int64_t a7 __asm__("a7") = 4;          // SYS_exit
    __asm__ volatile(
        ".word 0x00000073"
        :: "r"(a7)
        : "memory"
    );
    // shouldn't return
    __builtin_unreachable();
}

// Our startup string lives in .rodata — kernel identity-maps the whole
// RAM anyway (no page tables yet, U-mode inherits S-mode's physical view),
// so U-mode can read it directly.
static const char *msg = "U: hello from U-mode\n";

// Entry point — scheduler_create2 constructs a fake frame with sepc=this.
// We never return (there's nothing to return *to* — U-mode doesn't have
// a caller).  Loop forever, sys_write then sys_yield.
__attribute__((used)) void userapp_main(void) {
    while (1) {
        sys_write(msg, 20);          // length of "U: hello from U-mode\n"
        sys_yield();
    }
}
