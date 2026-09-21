> **[中文版本 →](zh-CN/CHANGELOG.md)**

# CHANGELOG — AeroOS 26R1

**Release**: AeroOS 26R1 (initial official Release)
**Published**: 2026-10-04
**Target platform**: riscv64 QEMU virt

---

## Core milestones

### Boot & Toolchain
- `68ab37e` / `5f537af` — Project initialization + QEMU virt bootable MVP
- `78004d8` — NS16550 UART driver + boot banner "AeroOS 26R1 booting..."
- `ba8964c` — Self-hosted aero-ld (Rust + nom), self-built RISC-V linker
- `82f8ede` — WSL `build.sh`, clang integrated-as + Windows-side aero.exe

### Memory management
- `ac98ad7` — Physical page-frame allocator, grows upward from `_kernel_end`
- `b1c73c6` — `kmalloc` / `kfree` on top of physical pages

### Interrupts & Scheduler
- `964047a` — Trap handler skeleton + CLINT driver stub (initially disabled)
- `5f6e149` — S-mode timer interrupt enabled (CLINT via legacy SBI `set_timer`)
- `4519b5c` — Preemptive round-robin scheduler, timer-tick driven
- `8efeca0` — Fixed timer self-test determinism
- **Root-cause bug fix**: `trap.S trap_return` now forces `SPIE=1`. Hardware trap entry clears SPIE; without this, `sret` sets `SIE = SPIE = 0` and interrupts are **permanently disabled**. See `docs/P1-验收报告.md` (Chinese) for the debug chronicle.
- **Root-cause bug fix**: `timer_enable()` must call `timer_arm()` (SBI `set_timer`) **before** enabling `STIE+SIE`. Without re-arming, MTIMECMP is already past `mtime` and will never trigger again.

### U-mode & Syscalls
- `9e4ea7a` — U-mode task framework + ecall dispatch (scause=8), 30-register 240B context frame, sys_write / sys_yield / sys_fork / sys_exit
- `ab98b33` — **Aero language binding**: `userapp.aero` uses `extern fn` + `syscall_shim.S` ecall wrappers, compiles into the kernel image, boots in QEMU and prints "hello from Aero"

### CI
- `3ce6eed` — GitHub Actions riscv64 QEMU virt boot verification workflow
- `429c23e` / `05d9012` — CI `tar` utime / permission issue fixes

---

## Performance baseline (P1.7 acceptance — measured values)

QEMU riscv64 virt, 10-second run window:

| Metric | Value |
|---|---|
| S-mode task counts | T0=331 T1=331 T2=331 T3=328 |
| Total scheduler ticks | 1,321 |
| U-mode ecalls | 58,565 |
| TRAP / panic / exception | 0 |
| ELF image size | 30,928 B |
| BIN image size | 8,612 B |

P1.7 full acceptance script: `test-boot.sh` + `test-interrupt.sh`. Both exit code 0 = all PASS.

---

## Known limitations (within 26R1 scope, non-blocking for release)

| Limitation | Reason |
|---|---|
| No PMP memory protection for U-mode | OpenSBI default PMP allows full-address-space U-mode access; adds complexity |
| Only 4 syscalls (write / yield / exit / fork) | Full POSIX surface needs file system + page tables |
| Timer interrupt period fixed at 0.2s | 10 MHz timebase + SBI `set_timer`; configurable in future |
| Hard real-time latency target (≤1 µs) not yet measured | Benchmark harness not written |
| EVT real hardware bring-up (VisionFive 2 / HiFive 1) | **NOT** a T-patch — classified as EVT (Engineering Verification Test). See [VERSIONING.md](VERSIONING.md) |

---

## What's next

| Phase | What |
|---|---|
| EVT | Bring up on VisionFive 2 / HiFive 1 — real hardware |
| 26R1 T-patch (when ready) | First OS-level bug fix or feature update → `T-26R1 00000` |
| 26R2 | Second Release of 26-line |
| 27H1 | First Release of 27-line (evolution / generation) |
