> **[中文版本 →](zh-CN/WRITING-UMODE-APPS.md)**

# Writing U-mode Apps — Aero userland for AeroOS 26R1

## How it works

```
userapp.aero                     syscall_shim.S                    trap.S                     api.c
───────────                      ───────────────                   ────────                   ─────
Aero source
 │
 ▼ aero --emit-obj --target riscv64-unknown-none
userapp.o (riscv64 object)
 │
 ▼ aero-ld + linker.ld → AeroOS-26R1-riscv64.elf
Single kernel image: S-mode kernel + U-mode userapp, linked together
 │
 ▼ QEMU -kernel → OpenSBI → kernel_start → scheduler_demo()
scheduler_create2(userapp_main, 1)    ← create U-mode task
 │
 ▼ timer interrupt + sret enters U-mode
userapp_main() runs!
```

**Key concept**: AeroOS 26R1 has no file system. The U-mode program is **not** a standalone ELF. It compiles to `.o` and gets linked into the kernel image alongside the S-mode code. This is what "single address space" (design principle 2) looks like in practice.

## Minimal working example

`myapp.aero`:
```aero
// 1. Declare syscalls. Aero v1.2.4 lacks inline asm for bare-metal targets,
//    so every syscall comes from an "extern C" shim in syscall_shim.S.
extern "C" fn sys_write(s: str, n: i64) -> i64;
extern "C" fn sys_yield();

// 2. #[no_mangle] — critical! Without this, Aero name-mangles the function
//    and scheduler_create2() cannot find it by symbol name.
#[no_mangle]
fn myapp_main() {
    let mut count = 0;
    loop {
        sys_write("hello from myapp\n", 17);
        count = count + 1;
        sys_yield();   // yield CPU — keeps S-mode tasks running too
    }
}
```

## Tell the scheduler to create this task

You have two options.

### Option 1 — Add it in `main.aero` (recommended, 26R1 default)

```aero
// main.aero
extern "C" fn scheduler_create2(entry: u64, priority: u64);

#[entry]
#[no_mangle]
fn kernel_start() {
    aeroos_uart_puts("AeroOS 26R1 booting...\n");
    scheduler_demo();        // default 4 S-mode + 1 U-mode tasks

    // ← add your task here:
    scheduler_create2(myapp_main as u64, 1);

    timer_enable();
    worker_0();
}
```

### Option 2 — Spawn from an existing U-mode task via `sys_fork` (untested in 26R1)

```aero
#[no_mangle]
fn myapp_main() {
    sys_write("hello\n", 6);
    // sys_fork(another_app as u64);   // spawns another U-mode task
}
```

## The syscall assembly shim

Aero v1.2.4 (released 2026-10-03) supports `asm!` for x86 but not for RISC-V bare-metal targets. The workaround is a small assembly file that Aero code can `extern "C"` against:

**`syscall_shim.S`** (you don't need to edit this):
```asm
    .section .text.userapp

# i64 sys_write(const char *s, i64 n)
    .globl  sys_write
    .type   sys_write, @function
sys_write:
    li   a7, 1
    ecall
    ret
    .size   sys_write, . - sys_write

# void sys_yield(void)
    .globl  sys_yield
    .type   sys_yield, @function
sys_yield:
    li   a7, 2
    ecall
    ret
    .size   sys_yield, . - sys_yield
```

`build.sh` compiles this to `syscall_shim.o` and links it alongside your `.aero` output.

## Build command

```bash
# 1. Compile Aero → riscv64 object
aero build myapp.aero --emit-obj --target riscv64-unknown-none
#    → myapp.o

# 2. Link everything together (build.sh does this for you)
aero-ld -T target/riscv64-qemu-virt/linker.ld \
        -o build/AeroOS-26R1-riscv64.elf \
        boot.o trap.o uart.o clint.o sched.o \
        myapp.o syscall_shim.o \
        main.o
```

## What `a7` numbers mean

| a7 | Macro name | Purpose |
|---|---|---|
| 1 | `SYS_WRITE` | Write to UART |
| 2 | `SYS_YIELD` | Voluntarily relinquish CPU |
| 3 | `SYS_EXIT` | Terminate this U-mode task |
| 4 | `SYS_FORK` | Create a new U-mode task |

Each number is a contract between `syscall_shim.S` (userland side) and `trap.S trap_ecall` (kernel side). Changing a number is a breaking ABI change.

## Debugging U-mode apps

**Method 1 — sys_write logging**
```aero
#[no_mangle]
fn myapp_main() {
    sys_write("ENTER myapp_main\n", 17);
    sys_write("before fork\n", 13);
    sys_fork(child_fn as u64);
    sys_write("after fork\n", 12);
}
```

**Method 2 — Run once then yield forever**
```aero
#[no_mangle]
fn myapp_main() {
    sys_write("hello once\n", 11);
    loop {
        sys_yield();   # park here while other tasks run
    }
}
```

**Method 3 — No QEMU graphics**
`run-qemu.sh` uses `-nographic`. If your code crashes, the trap handler prints a panic + register dump to UART. Read the output — it contains `sepc`, `scause`, and all 30 registers — that's everything you need.

## Known limitations (26R1)

| Limitation | Reason |
|---|---|
| No inline asm in Aero (riscv64 target) | v1.2.4 parser gap |
| No stdlib | AeroOS has no libc, no heap exposed to U-mode |
| No `malloc` | U-mode heap allocator not exposed |
| No file system | No initrd, no virtio-blk, no FAT/ext2 driver |
| No PMP memory protection | OpenSBI default PMP allows U-mode full address access |
| `linker.ld` addresses are hardcoded | U-mode entry points must match specific virtual addresses |

All of these are trackable. None are architectural blockers.

## Repository structure (reference)

```
AeroOS-26R1/
├── kernel/src/
│   ├── main.aero                    # #[entry] kernel_start()
│   ├── userapp.aero                 # official U-mode demo app
│   ├── boot/riscv64/start.S         # boot entry
│   ├── boot/riscv64/trap.S          # trap handler + syscall dispatch
│   ├── sched.c                      # scheduler_create2(), aeroos_sys_fork()
│   └── syscall_shim.S               # ecall wrappers (U-mode → S-mode bridge)
├── target/riscv64-qemu-virt/
│   └── linker.ld                    # controls section addresses
├── build.sh                         # one-command build
└── run-qemu.sh                      # one-command run
```

## See also

- [SYSCALLS.md](SYSCALLS.md) — full a7 table, argument layouts, backend source
- [API-REFERENCE.md](API-REFERENCE.md) — complete kernel and user API inventory
- [ARCHITECTURE.md](ARCHITECTURE.md) — context frame, trap flow, U-mode task creation internals
