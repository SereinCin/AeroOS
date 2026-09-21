> **[中文版本 →](zh-CN/HARDWARE.md)**

# Hardware — QEMU virt Platform Reference

26R1 targets **QEMU riscv64 virt** (`-machine virt`). This page documents the exact memory map, device registers, and timer behavior you need when writing drivers or porting to real hardware.

## Platform summary

| Item | Value |
|---|---|
| QEMU machine | `riscv64 virt` |
| CPU | Single hart, RV64GC |
| RAM | 128 MB (default) |
| BIOS | OpenSBI v1.3, FW_DYNAMIC mode |
| Timer | ACLINT MTIMER @ 10 MHz (timebase = 0.1 µs / tick) |
| Console | UART8250 (NS16550 compatible) @ 1.8432 MHz crystal |

## Full physical address map

```
0x00000000 ──────────────────────────────────────────┐
                                                      │ MMIO
0x10000000 ─────────┐                                │
                     │ NS16550 UART0 (UART8250)       │ Device registers
0x100000C0 ─────────┤ (3.3V, 115200 8N1)             │
                     │                                │
0x20000000 ─────────┤ QEMU virt reserved MMIO        │
                     │                                │
0x80000000 ─────────┐                                │
                     │ OpenSBI FW_DYNAMIC             │ Firmware
0x8004FFFF ─────────┘ (~322 KB)                       │
                     │                                │
0x80080000 ─────────┐                                │
                     │ ACLINT MTIMER (read-only)      │ Timer
0x800BFFFF ─────────┤ ACLINT MSWI (machine software)  │
0x800FFFFF ─────────┘                                │
                                                      │
0x80200000 ─────────┐                                │
                     │ AeroOS kernel image (loaded by  │ Kernel
                     │ OpenSBI FW_DYNAMIC per ELF      │
                     │ segments)                       │
                     │                                  │
                     │ .text + .rodata + .data: ~65 KB  │
0x80303000 ─────────┤ _kernel_end                      │
                     │ kmalloc / page allocator heap    │ Heap
                     │                                  │
                     │                                  │
0x88000000 ─────────┘ QEMU virt RAM top (128 MB)     │ RAM
```

## NS16550 UART

**Base address**: `0x10000000`

| Offset | Read | Write |
|---|---|---|
| +0 | RBR (Receive Buffer) | THR (Transmit Holding) |
| +1 | IER | IER |
| +2 | IIR | FCR |
| +3 | LCR | LCR |
| +4 | MCR | MCR |
| +5 | LSR | — |
| +6 | MSR | — |
| +7 | SCR | SCR |

**Baud rate**: QEMU hardcodes 115200, 8 data bits, no parity, 1 stop bit. The divisor register path (DLAB bit + DLL/DLM) exists but QEMU does not actually change the rate.

**26R1 driver** (`uart.c`):
```c
#define UART0_THR  0x10000000
#define UART0_LSR  (UART0_THR + 5)

void aeroos_uart_putc(char c) {
    // Wait until THR is empty (LSR bit 5 = 1)
    while ((*(volatile uint8_t*)UART0_LSR & 0x20) == 0) {}
    *(volatile uint8_t*)UART0_THR = c;
}
```

## CLINT MTIMER — The Most Important Timer

**Base address**: `0x80080000` (on QEMU virt — this varies by board!)

**Frequency**: 10 MHz → each tick = 0.1 µs. So 0.2s = 2,000,000 ticks.

### Why we use SBI `set_timer` instead of writing CLINT directly

OpenSBI v1.3 handles the MTIMERCMP register. From S-mode we can only call:
```
li   a7, 0              # legacy SBI Extension ID = 0 (Set Timer)
ecall                   # a1 = new compare value
```
OpenSBI writes `a1` into MTIMERCMP and re-enables the timer. Direct S-mode writes to CLINT registers are intercepted by OpenSBI.

### Timer interrupt handler — must do two things

```c
void irq_timer(void) {
    // 1. RE-ARM the timer ← WITHOUT THIS, MTIP will never fire again
    uint64_t next = read_mtime() + 2000000;   // next fire in 0.2s
    sbi_set_timer(next);                       // SBI call

    // 2. Open interrupts
    csrs sie, (1 << 5);     // STIE (bit 5)
    csrs sstatus, (1 << 1); // SIE   (bit 1)
}
```

**Root cause bug (26R1)**: If you only do step 2 (enable STIE + SIE) but skip step 1, MTIMECMP is already past `mtime` and will never trigger again. The timer interrupt fires **once** then the OS hangs. See `docs/P1-验收报告.md` for the full bug hunt.

### `timer_enable()` — the actual code path

```c
void timer_enable(void) {
    timer_arm(TIMER_INTERVAL);      // step 1: arm MTIMECMP
    csrs sie, (1 << 5);             // step 2: STIE
    csrs sstatus, (1 << 1);         // step 3: SIE
}
```

## OpenSBI FW_DYNAMIC boot flow

OpenSBI v1.3 boots QEMU virt with FW_DYNAMIC — it does **not** hardcode the kernel address.

```
M-mode: OpenSBI
 │  1. Initialize PMP (allow kernel RAM access)
 │  2. Initialize timer + console (UART)
 │  3. Read -kernel argument → parse ELF header
 │  4. Load ELF segments into RAM
 │  5. Jump to ELF entry (0x80200000 = _start)
 │
 ▼
M-mode → S-mode transition (sret with SPP=1)
 │  satp = 0 (bare mode, no page tables)
 │  medany code model
 │
 ▼
_start (boot/riscv64/start.S)
```

Linker script:
```ld
ENTRY(_start)
SECTIONS {
    . = 0x80200000;
    .text : { ... }
    .rodata : { ... }
    .data : { ... }
    _kernel_end = .;
}
```

## QEMU launch command — annotated

```bash
qemu-system-riscv64 \
    -machine virt               # Provides: OpenSBI FW_DYNAMIC + CLINT + UART + PLIC
    -bios default               # Bundled OpenSBI v1.3 — no need to download firmware
    -kernel AeroOS-26R1-riscv64.elf  # OpenSBI parses this ELF, loads segments, jumps to entry
    -nographic                  # No GUI window — UART goes straight to terminal
    -monitor none                # Disable QEMU monitor (Ctrl-A C would otherwise open it)
    -smp 1                       # Single hart (26R1 is not SMP)
    -m 128M                      # 128 MB RAM (explicit; default is also 128M)
```

## Porting checklist — QEMU virt → real hardware

| Component | QEMU virt value | What real boards vary on |
|---|---|---|
| UART base | `0x10000000` | VisionFive 2: same; HiFive 1: `0x10010000` |
| Timer frequency | 10 MHz | VisionFive 2: same; other boards may differ |
| CLINT base | `0x80080000` | Some boards use `0x20000000` |
| OpenSBI | QEMU-bundled | Build your own FW_DYNAMIC firmware per board |
| Boot media | `-kernel` direct load | SD card / SPI NOR → OpenSBI loads kernel from media |
| RAM size | 128 MB | Usually 2 GB+ on real boards |
| SMP | 1 hart | Many RISC-V boards are multi-core (26R1 is single-core only) |

> **EVT note**: Real hardware bring-up for VisionFive 2 / HiFive boards is tracked as EVT (Engineering Verification Test), not as a T-patch. See [VERSIONING.md](VERSIONING.md) for the boundary.

## CSR cheat sheet (RISC-V 64-bit supervisor)

| CSR | 26R1 sets it | Purpose |
|---|---|---|
| `sstatus.SPP` | task frame init | Return mode: 0 = U, 1 = S |
| `sstatus.SPIE` | trap_return (forced to 1!) | Re-enable SIE on `sret` |
| `sstatus.SIE` | timer_enable | Supervisor interrupt enable |
| `sie.STIE` | timer_enable | Timer interrupt enable (bit 5) |
| `sepc` | trap entry | Where `sret` returns to |
| `sscratch` | trap entry | Swap buffer for sp on trap |
| `scause` | trap entry | Interrupt cause (5 = timer, 8 = ecall) |
| `medeleg` | OpenSBI sets it | S-mode delegation of certain exceptions |
| `mideleg` | OpenSBI sets it | S-mode delegation of certain interrupts |
| `satp` | 0 (bare mode) | Address translation mode; 0 = no translation |

### Key bit constants

```
sstatus.SPP  = 1 << 8       # Previous privilege mode
sstatus.SPIE = 1 << 5       # Previous interrupt enable (★ trap.S forces this back to 1!)
sstatus.SIE  = 1 << 1       # Supervisor interrupt enable
sie.STIE     = 1 << 5       # Timer interrupt enable (in sie, not sstatus)
```

## See also

- [ARCHITECTURE.md](ARCHITECTURE.md) — trap flow, context frame, scheduler with timer interrupts
- [SYSCALLS.md](SYSCALLS.md) — ecall flow from U-mode to S-mode
- [QUICKSTART.md](QUICKSTART.md) — annotated QEMU command in one-command run context
