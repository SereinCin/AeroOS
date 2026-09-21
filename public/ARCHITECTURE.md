> **[中文版本 →](zh-CN/ARCHITECTURE.md)**

# Architecture — AeroOS 26R1

## Boot chain

```
QEMU riscv64 virt
 │
 └─ OpenSBI v1.3 (FW_DYNAMIC)          @ 0x80000000 (~322 KB)
     │
     │  1. Load AeroOS-26R1-riscv64.elf into RAM (per ELF segments)
     │  2. Set satp=0 (bare mode), medany code model
     │  3. sret to S-mode (SPP=1, SPIE=1, SPV=1)
     │
     ▼
_start (kernel/src/boot/riscv64/start.S)  @ 0x80200000
     │  set stack pointer, zero BSS
     ▼
kernel_start (main.aero, #[entry])
     │
     ├─ uart_init()       ← NS16550 setup
     ├─ scheduler_demo()  ← create 4 S-mode + 1 U-mode tasks
     ├─ timer_enable()    ← STIE + SIE + SBI set_timer
     │
     └─ worker_0() ← halt loop; timer interrupt preempts and round-robins
```

## Physical memory map (QEMU virt)

```
0x00000000 ─┐
             │ MMIO
0x10000000 ─┤ NS16550 UART0 (3.3V, 115200 8N1)
0x100000C0 ─┤ ...
0x20000000 ─┤ QEMU virt reserved MMIO
0x80000000 ─┤ OpenSBI FW_DYNAMIC (~322 KB)
0x8004FFFF ─┤
0x80080000 ─┤ ACLINT MTIMER (10 MHz, read-only)
0x800BFFFF ─┤ ACLINT MSWI
0x80200000 ─┤ AeroOS kernel image (text + rodata + data, ~65 KB)
0x802FFFFF ─┤
0x80300000 ─┤ _kernel_end = heap start (kmalloc / page allocator)
             │
0x88000000 ─┘ QEMU virt RAM top (128 MB)
```

## Context frame (240 bytes)

Every task (S-mode or U-mode) carries a 30-register frame on its own stack.

```c
struct context_frame {
    uint64_t ra;      // ra
    uint64_t t0;      // t0 - t6 (7 regs)
    uint64_t t1;
    ...
    uint64_t t6;
    uint64_t a0;      // a0 - a7 (8 regs)
    ...
    uint64_t a7;
    uint64_t s0;      // s0 - s11 (12 regs)
    ...
    uint64_t s11;
    uint64_t sepc;    // program counter (where to sret to)
    uint64_t sstatus; // supervisor status register (SPP=0 → U-mode, 1→S-mode)
};
// 30 regs × 8 B = 240 B
```

### trap entry (trap.S)

```asm
trap_entry:
    csrrw   sp, sscratch, sp     # exchange sp (save current task's sp)
    addi    sp, sp, -240         # allocate 240B frame on this task's stack
    sd      ra,    0(sp)
    sd      t0,    8(sp)
    ...                           # push all 30 registers
    sd      s11, 216(sp)
    csrr    t0, sepc
    sd      t0,  224(sp)
    csrr    t0, sstatus
    sd      t0,  232(sp)
    csrrw   sp, sscratch, sp     # restore sp (now pointing back to stack top)
    # → dispatch to handler (timer / ecall / exception)
```

### trap_return (trap.S)

```asm
trap_return:
    ld      ra,    0(sp)
    ld      t0,    8(sp)
    ...                           # pop all 30 registers
    ld      s11, 216(sp)
    ld      t0,  224(sp); csrw sepc,    t0
    ld      t0,  232(sp)
    ori     t0, t0, 0x20          # ★ force SPIE=1 (critical — hardware trap clears it!)
    csrw    sstatus, t0
    addi    sp, sp, 240
    sret                           # returns to mode specified by SPP (0→U, 1→S)
```

> **Why force SPIE=1?** Hardware trap entry automatically clears SPIE. If we don't force it back, `sret` sets `SIE = SPIE = 0` and interrupts are **permanently disabled**. This was the most subtle bug in 26R1 — see `docs/P1-验收报告.md` (Chinese) for the bug-hunt chronicle.

## Preemptive scheduler

```
Timer interrupt (scause=5, every 0.2s @ 10 MHz)
 │
 ▼
trap_timer (trap.S):
  1. rdtime + SBI set_timer → re-arm (NO this step = MTIP never fires again)
  2. current_task->saved_sp = sp      ← save current frame bottom
  3. scheduler_tick() (C function)   ← round-robin pick next task
  4. sp = next_task->saved_sp
  5. j trap_return → sret into new task
```

Round-robin order: `T0 → T1 → T2 → T3 → U-mode userapp → T0 → ...`

Eligibility: any task with `saved_sp != 0`. All tasks are created at boot with `saved_sp` set to their stack's frame bottom.

## Syscall flow (U-mode → S-mode)

Aero (userland) → asm shim → trap dispatch → C backend → trap_return → sret → back to userland.

```
userapp.aero                   syscall_shim.S                trap.S                   api.c / trap.S
───────────                    ───────────────                ────────                 ──────────────
sys_write("hello", 16);
 │
 ▼ (extern "C")
sys_write:
    li   a7, 1                 ← syscall number
    ecall                      ← scause=8 → trap_ecall
    ret
                                  │
                                  ▼ trap_ecall:
                                  a7==1 → aeroos_sys_write()      (C backend)
                                  a7==2 → asm yield handler       (inline in trap.S)
                                  a7==3 → asm exit handler        (inline in trap.S)
                                  a7==4 → aeroos_sys_fork()      (C backend)
                                  │
                                  ▼
                                  execute + trap_return + sret
                                  │
                                  ▼ back to userapp
```

| a7 | Syscall | Backend |
|---|---|---|
| 1 | `sys_write` | `aeroos_sys_write()` in `sched.c` |
| 2 | `sys_yield` | asm handler in `trap.S` (directly calls `scheduler_tick`) |
| 3 | `sys_exit` | asm handler in `trap.S` |
| 4 | `sys_fork` | `aeroos_sys_fork()` in `sched.c` |

## U-mode task creation

```c
// S-mode kernel creates a U-mode task:
scheduler_create2(userapp_main /* entry address */, 1 /* priority, reserved */);
```

`scheduler_create2` initializes the context frame with:
- `sepc = userapp_main` (entry address)
- `sstatus.SPP = 0` → sret returns to U-mode
- `sstatus.SPIE = 1` → interrupts re-enable on sret
- all 30 GP regs = 0
- task's own stack = 8 KB (allocated from heap)

## Languages

| Component | Language |
|---|---|
| Boot entry + trap handler | Assembly (RISC-V asm in `trap.S`, `start.S`) |
| Drivers / scheduler / syscall backends | C |
| Kernel entry + userland apps | [Aero 1.2.4](https://github.com/SereinCin/aero-lang) |
| Linker | aero-ld (self-hosted, Rust + nom) |

## Key data structures

**Task** (`sched.c`)
```c
typedef struct task {
    uint64_t saved_sp;       // context frame bottom (also the task's stack pointer after trap entry)
    uint64_t entry;          // entry point (U-mode or S-mode virtual address)
    uint8_t  is_umode;       // 1 = U-mode, 0 = S-mode
} task_t;
```

**Physical page allocator** (`phys.c`)
```c
// Linear bump from _kernel_end. Each call = one 4 KB page.
void *aeroos_alloc_page(void);
void  aeroos_free_page(void *p);
```

**Heap** (`heap.c`)
```c
// kmalloc/kfree built on top of physical pages. Fast path = zero alloc (design principle 3),
// but scheduler needs it for task stacks.
void *kmalloc(size_t size);
void  kfree(void *p);
```

## See also

- [HARDWARE.md](HARDWARE.md) — QEMU virt platform details, UART, CLINT, OpenSBI
- [SYSCALLS.md](SYSCALLS.md) — full syscall table with a7 numbers and argument layouts
- [API-REFERENCE.md](API-REFERENCE.md) — complete C / Aero API signatures
- [WRITING-UMODE-APPS.md](WRITING-UMODE-APPS.md) — how to build your own U-mode Aero program
