# syscall_shim.S — thin U-mode syscall wrappers that Aero (and C) userland
# can call as ordinary functions.  Each wrapper does nothing but set a7 to
# the syscall number and issue ecall, which traps into S-mode trap.S's
# ecall dispatch (scause code=8).
#
# These names are intentionally DIFFERENT from the C backend symbols in
# api.c (aeroos_sys_write / aeroos_sys_fork) — aero-ld would otherwise see
# duplicate definitions.  The C backend is called by trap.S's ecall
# handlers; these shims are called by userland code before issuing ecall.

    .text

# i64 sys_write(const char *s, i64 n)
    .globl  sys_write
    .type   sys_write, @function
sys_write:
    li      a7, 1                       # SYS_write
    ecall
    ret
    .size   sys_write, . - sys_write

# void sys_yield()
    .globl  sys_yield
    .type   sys_yield, @function
sys_yield:
    li      a7, 2                       # SYS_yield
    ecall
    ret
    .size   sys_yield, . - sys_yield

# void sys_exit()
    .globl  sys_exit
    .type   sys_exit, @function
sys_exit:
    li      a7, 4                       # SYS_exit
    ecall
    ret
    .size   sys_exit, . - sys_exit
