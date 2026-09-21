> **[中文版本 →](zh-CN/SYSCALLS.md)**

# Syscall Table — AeroOS 26R1

## Overview

U-mode userland issues an **ecall** instruction to trap into S-mode. `trap.S`'s `trap_ecall` handler dispatches based on the `a7` register.

```
U-mode:  li   a7, <syscall_number>
         ecall                 # scause = 8 → trap_ecall
                            ↓
trap.S:  trap_ecall (scause & 0x3FF == 8)
              ↓
         a7 == 1 → aeroos_sys_write()       (C backend)
         a7 == 2 → yield  (asm handler)      (inline in trap.S)
         a7 == 3 → exit   (asm handler)      (inline in trap.S)
         a7 == 4 → aeroos_sys_fork()         (C backend)
              ↓
         trap_return → sret → back to U-mode
```

## Full syscall table

| a7 | Name | a0 | a1 | a2 | Backend | 26R1 |
|---|---|---|---|---|---|---|
| 1 | `sys_write` | `s: str*` | `n: i64` | — | C `aeroos_sys_write()` | ✅ |
| 2 | `sys_yield` | — | — | — | asm yield | ✅ |
| 3 | `sys_exit` | — | — | — | asm exit | ✅ |
| 4 | `sys_fork` | `entry: u64` | — | — | C `aeroos_sys_fork()` | ✅ |

Argument register convention follows the standard RISC-V calling convention: a0 – a7 for arguments, a0 for return value.

## sys_write (a7 = 1)

**C signature**:
```c
int64_t sys_write(const char *s, int64_t n);
```

**Aero declaration**:
```aero
extern "C" fn sys_write(s: str, n: i64) -> i64;
```

| Register | Meaning |
|---|---|
| a0 | String pointer (U-mode virtual address) |
| a1 | Byte count to write |

Returns (a0): actual bytes written. Success = `min(n, strlen(s))`. Failure = -1.

**Assembly example**:
```asm
    li   a7, 1
    la   a0, msg           # "hello\n"
    li   a1, 6
    ecall
    # a0 = 6 on success
```

**Aero example**:
```aero
sys_write("hello from Aero\n", 16);
```

Backend (`sched.c`):
```c
int64_t aeroos_sys_write(const char *s, int64_t n) {
    int64_t written = 0;
    for (int64_t i = 0; i < n; i++) {
        if (s[i] == '\0') break;
        aeroos_uart_putc(s[i]);    # hardware-backed; no UART FIFO magic
        written++;
    }
    return written;
}
```

> Note: 26R1 directly dereferences the U-mode pointer. OpenSBI's default PMP allows full-address-space U-mode access, so this works. When PMP memory protection is added (future version), this needs a proper `copy_from_user`.

## sys_yield (a7 = 2)

**Parameters**: none
**Return**: normal return (the same U-mode code continues, but may be on a different CPU or after other tasks ran — in 26R1 it's a single core, so just round-robined)

**Why it matters**: AeroOS uses a dual-track scheduler:
- U-mode tasks **voluntarily yield** → fairness without starvation
- Timer interrupt (0.2s period) **forcibly preempts** → guaranteed non-starvation for tasks that never yield

S-mode kernel code **cannot** call this — S-mode doesn't have ecall permissions in the same way; the scheduler ticks via `scheduler_tick()` directly.

Backend (inline asm in `trap.S`):
```asm
trap_yield:
    call    scheduler_tick
    mv      sp, a0               # switch to next task's frame
    j       trap_return
```

## sys_exit (a7 = 3)

Terminates the calling U-mode task. Context frame remains resident in memory — task stack is not reclaimed in 26R1 (known limitation). Future versions will add proper cleanup and a `sys_wait` / `sys_reap` pair.

## sys_fork (a7 = 4)

Spawn a new U-mode task from U-mode.

| Register | Meaning |
|---|---|
| a0 | New task's entry point (virtual address in U-mode code segment) |

Returns (a0): new task's numeric ID (≥ 0 on success), -1 on failure.

**C declaration**:
```c
int64_t sys_fork(uint64_t entry);
```

**What it does**:
1. Allocates a new 8 KB stack for the new task
2. Initializes a context frame: `sepc = entry`, `sstatus.SPP = 0` (U-mode), all GP regs = 0
3. Calls `scheduler_create2(entry, 1)`
4. Returns the new task's index into the task table

**Important constraints**:
1. `entry` must point into the U-mode code section. `aero-ld` places this at a known virtual address — the linker script controls this.
2. The new task **shares the same address space** with the parent (single-address-space design principle 2). No page-table copying, no COW.
3. There is no parent/child PID distinction. Just two U-mode tasks.

## Adding a new syscall

1. **C backend** — add `int64_t aeroos_sys_xxx(...)` in `api.c`
2. **trap.S dispatch** — add a case in `trap_ecall`:
   ```asm
   li    t2, <new_a7>
   beq   t2, a7, trap_xxx
   ```
3. **asm shim** — add in `syscall_shim.S`:
   ```asm
   .globl  sys_xxx
   .type   sys_xxx, @function
   sys_xxx:
       li   a7, <new_a7>
       ecall
       ret
   .size   sys_xxx, . - sys_xxx
   ```
4. **Update docs** — `SYSCALLS.md`, `API-REFERENCE.md` (English + zh-CN)

## Known limitations

| Limitation | Reason | Plan |
|---|---|---|
| Only 4 syscalls | 26R1 scope: boot + scheduler + U-mode demo | Full POSIX surface (open/read/close/mmap/execve/signal) = file system + page tables |
| `sys_write` dereferences U-mode pointer directly | OpenSBI PMP allows it | Add `copy_from_user` when PMP protection lands |
| `sys_fork` does not copy address space | Single-address-space principle 2 | Future `sys_spawn` for true isolation if needed |
| No PID / wait / reap | 26R1: tasks are round-robined, no task lifecycle management | `sys_wait`, `sys_reap` |
| No `brk` / `mmap` for U-mode heap | No U-mode heap allocator exposed | P2+ |
