> **[中文版本 →](zh-CN/README.md)**

# AeroOS 26R1

> Hard real-time OS kernel written from scratch in Aero.
> RISC-V QEMU virt · 26R release line · Apache-2.0

---

## What is AeroOS

AeroOS is a **hard real-time operating system kernel**. The goal: **deterministically low interrupt-to-thread latency** (≤1µs target for the 26R series). Written from scratch in [Aero](https://github.com/SereinCin/aero-lang) — a systems programming language designed for exactly this use case.

**26R1 is the first official Release** of AeroOS. Target platform: **RISC-V 64-bit QEMU virt**. It boots end-to-end on OpenSBI FW_DYNAMIC, runs a preemptive scheduler, serves U-mode tasks via syscalls, and ships with an Aero-written userland program.

> On hardware availability: EVT (Engineering Verification Test) on real RISC-V boards is **DEFERRED** — see [VERSIONING.md](VERSIONING.md) for why this is not a T-patch. 26R1 is fully gate-passed for the QEMU virt target.

## What you can do here

| If you want to… | Read |
|---|---|
| Get it running in 10 minutes | [QUICKSTART.md](QUICKSTART.md) |
| Understand how the kernel works | [ARCHITECTURE.md](ARCHITECTURE.md) — boot chain, scheduler, context switch |
| Write a userland program in Aero | [WRITING-UMODE-APPS.md](WRITING-UMODE-APPS.md) |
| Look up C / Aero API signatures | [API-REFERENCE.md](API-REFERENCE.md) |
| Reference the syscall table | [SYSCALLS.md](SYSCALLS.md) |
| Target hardware details (address map, timers) | [HARDWARE.md](HARDWARE.md) |
| Understand the 26 / 27 / LTS / STS / T-patch naming | [VERSIONING.md](VERSIONING.md) |
| See what changed | [CHANGELOG.md](CHANGELOG.md) |

## Core features (26R1)

| Module | Status |
|---|---|
| Boot + OpenSBI FW_DYNAMIC handoff | ✅ |
| NS16550 UART console | ✅ |
| Physical page allocator | ✅ |
| `kmalloc` / `kfree` on physical pages | ✅ |
| CLINT MTIMER via legacy SBI `set_timer` | ✅ |
| Preemptive round-robin scheduler | ✅ |
| 30-register 240-byte context frame | ✅ |
| U-mode tasks + ecall dispatch (scause=8) | ✅ |
| Aero-language U-mode app linked into kernel image | ✅ |

## Design principles (never violate)

1. **Determinism over average speed.** Worst-case matters most.
2. **Single address space.** No page table switches, no TLB shootdown.
3. **Fast path = zero allocation.** Any `malloc` means unbounded jitter.
4. **Interrupts reach threads directly.** No generic framework, no dispatch, no accounting.
5. **No global interrupt-disable / preemption-disable critical sections.** Use priority masking.
6. **Measurement infrastructure is first-class.** Built with the kernel, not after.

## Repository structure (26R1)

```
kernel/
  src/
    boot/riscv64/start.S        # Boot entry (assembly)
    boot/riscv64/trap.S         # Trap handler + syscall dispatch
    driver/riscv64/             # UART, CLINT, stubs
    mm/                         # Page allocator + heap
    sched.c                     # Scheduler + syscall backends
    syscall_shim.S              # ecall wrappers for U-mode → S-mode
    main.aero                   # #[entry] kernel_start()
    userapp.aero                # Aero-written U-mode demo app
    Aero.toml                   # Aero package config
target/
  riscv64-qemu-virt/
    linker.ld                   # Custom linker script (0x80200000 entry)
release.sh                      # Builds public .zip packages
run-qemu.sh                     # One-command QEMU launch
test-boot.sh / test-interrupt.sh # P1.7 acceptance scripts (.exit 0 = all PASS)
public/                         # ← You are here
docs/                           # Internal design docs, P1 acceptance report
```

## Names

| Role | Value |
|---|---|
| Display name | `AeroOS 26R1` |
| Technical name | `aeroos-26r1` (all-lowercase, dashes) |
| Kernel image | `AeroOS-26R1-riscv64.elf` / `.bin` |
| Zip packages | `aeroos-26r1-riscv64-qemu.zip`, `aeroos-26r1-source.zip` |
| Version string | `26R1` (birth year 2026 + Release + serial 1) |

See [VERSIONING.md](VERSIONING.md) for the full 26 / 27 / LTS / STS / T-patch rules.

## License

Apache-2.0. See the LICENSE file. GPL's strong copyleft would deter adoption in commercial real-time systems — that choice is intentional.
