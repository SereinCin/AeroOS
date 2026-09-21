> **[中文版本 →](zh-CN/API-REFERENCE.md)**

# API Reference — AeroOS 26R1

AeroOS 26R1 exposes two API surfaces — kernel-space (S-mode, C / Aero via `extern "C"`) and user-space syscalls (U-mode, `ecall`). Syscalls are documented fully in [SYSCALLS.md](SYSCALLS.md).

---

## Kernel-space API (S-mode)

### UART

```c
void aeroos_uart_puts(const char *msg);
```
Print null-terminated string to NS16550 UART0. Blocks until all bytes are transmitted.

```c
void aeroos_uart_putc(char c);
```
Print a single character.

**Aero declaration** (`extern "C"`):
```aero
extern "C" fn aeroos_uart_puts(msg: str);
```

### Timer

```c
void timer_enable(void);
```
Starts the timer interrupt. Internally: calls SBI `set_timer` to arm a new MTIMECMP, then sets `STIE` (bit 5 of `sie`) and `SIE` (bit 1 of `sstatus`). Without the `set_timer` arm, the timer is **never** re-triggered — this was a root-cause bug fixed in 26R1 (see `docs/P1-验收报告.md`).

```c
uint64_t clint_mtime_read(void);
```
Read CLINT `mtime` counter (10 MHz timebase on QEMU virt). Returns current timestamp in 0.1µs units.

```c
void aeroos_wait_timer_ticks(int64_t n);
```
Busy-wait for n timer interrupts. Used in boot self-test only.

### Scheduler

```c
int scheduler_create(void (*entry)(void));
```
Create an S-mode task. `entry` is a C function pointer. Initial task status = S-mode (SPP=1).

```c
int scheduler_create2(uint64_t entry, uint8_t priority);
```
Create either S-mode or U-mode task. `entry` is a **virtual address** (any mode). This is the primary API for creating U-mode tasks — pass a U-mode function's address and the frame is initialized with `sstatus.SPP = 0`. `priority` is reserved for future use, pass 1.

```c
uint64_t scheduler_tick(void);
```
Round-robin to the next eligible task (eligible = `saved_sp != 0`). Returns the new task's `saved_sp`. Called by `trap.S` after saving the current task's frame.

```c
void scheduler_demo(void);
```
Boot-time helper: creates 4 S-mode worker tasks (`worker_0` – `worker_3`) + 1 U-mode Aero userapp (`userapp_main`).

### Memory

```c
void *aeroos_alloc_page(void);
void  aeroos_free_page(void *p);
```
Physical page allocator. Each call reserves or returns one 4 KB page. Pages are allocated upward from `_kernel_end`.

```c
void *kmalloc(size_t size);
void  kfree(void *p);
```
Kernel heap allocator, built on top of physical pages. **Design principle 3** says the fast path = zero allocation, but scheduler and task creation need it for task stacks.

---

## User-space Syscalls (U-mode)

Full table with argument layouts: [SYSCALLS.md](SYSCALLS.md).

**Aero declarations** (what you `extern "C"` in your userland program):
```aero
extern "C" fn sys_write(s: str, n: i64) -> i64;
extern "C" fn sys_yield();
extern "C" fn sys_exit();
extern "C" fn sys_fork(entry: u64) -> i64;
```

**Syscall shim**: Aero currently (v1.2.4) does not support inline assembly for bare-metal targets. Every syscall goes through an assembly wrapper in `syscall_shim.S` — that wrapper sets `a7` and issues `ecall`. This is why Aero code can just `extern "C" fn sys_write(...)` and call it like any other function.

---

## Complete symbol inventory

### Kernel (C / extern "C")

| Symbol | File | Purpose |
|---|---|---|
| `aeroos_uart_puts` | `sched.c` | Print string |
| `aeroos_uart_putc` | `sched.c` | Print char |
| `aeroos_sys_write` | `sched.c` | Syscall backend for a7=1 |
| `aeroos_sys_fork` | `sched.c` | Syscall backend for a7=4 |
| `scheduler_create` | `sched.c` | Create S-mode task |
| `scheduler_create2` | `sched.c` | Create S/U-mode task |
| `scheduler_tick` | `sched.c` | Round-robin pick next |
| `scheduler_demo` | `sched.c` | Boot task spawning |
| `timer_enable` | `clint.c` | Start timer interrupt |
| `clint_mtime_read` | `clint.c` | Read mtime |
| `aeroos_wait_timer_ticks` | `clint.c` | Wait N ticks |
| `aeroos_alloc_page` | `phys.c` | 4 KB page alloc |
| `aeroos_free_page` | `phys.c` | Free page |
| `kmalloc` / `kfree` | `heap.c` | Heap allocator |
| `worker_0` – `worker_3` | `sched.c` | S-mode worker entry points |

### User-space (ecall via syscall_shim.S)

| Symbol | a7 | Purpose |
|---|---|---|
| `sys_write` | 1 | Write string to UART |
| `sys_yield` | 2 | Voluntarily relinquish CPU |
| `sys_exit` | 3 | Terminate current U-mode task |
| `sys_fork` | 4 | Spawn a new U-mode task |

---

## Naming rules

- Kernel symbols: `aeroos_*` prefix or domain verb (`scheduler_*`, `timer_*`, `kmalloc`, etc.)
- Syscalls: `sys_*` prefix (POSIX-convention, familiar to C/Unix developers)
- Internal-only (static): no public symbol

**Not present in 26R1**: open / close / read / mmap / munmap / execve / signal. No file system, no page tables, no POSIX fork semantics — sys_fork creates a new U-mode task sharing the same address space (single-address-space design principle 2).
