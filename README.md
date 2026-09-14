# AeroOS

> AeroOS — hard real-time OS kernel written from scratch in Aero.  
> Apache-2.0 licensed. First release: 26R1.

## What is AeroOS

AeroOS is a hard real-time operating system kernel. The goal is simple:
**deliver deterministically low interrupt and scheduling latency**, and
publish verifiable numbers (end-to-end interrupt-to-thread ≤1µs target).

AeroOS is written in [Aero](https://github.com/SereinCin/aero-lang), a
system programming language designed for this exact use case.

## Architecture matrix

| Platform | 26R series | 27 | 27Pro |
|----------|:----------:|:--:|:-----:|
| RISC-V   | ✅ primary  | —  |   —   |
| x86_64   |     ✅      | ✅ |   ✅   |
| x86_64 server |    —    | ✅ |   ✅   |
| ARM64    |     ✅      | ✅ |   ✅   |
| PowerPC / Power ISA | — | —  |   ✅   |
| LoongArch LA64 | —    | —  |   ✅   |

- **26R** — broad coverage, continuous release train. → R1 → R2 → R3 → **26R3-STS**
- **27 / 27Pro** — x86_64 server focus, parallel line (not a replacement for 26R)

## Repository structure (26R1)

```
kernel/
  src/
    boot/riscv64/start.S    # Pure assembly boot entry
    driver/riscv64/         # UART, timer, interrupt controller drivers
    main.aero               # #[entry] kernel_start()
  Aero.toml                 # Aero package config
target/
  riscv64-qemu-virt/
    linker.ld               # Custom linker script
    Makefile                # Build script
docs/
  architecture.md           # Design principles & roadmap
```

## Quick start (riscv64 QEMU virt)

```bash
cd target/riscv64-qemu-virt
make          # boot.o + kernel.o → AeroOS.elf
make run      # QEMU virt console
```

## License

Apache-2.0. See `LICENSE` for full text. This is intentional — GPL's strong
copyleft would deter adoption in commercial real-time systems.

---

**Design principles** — the anchor for every decision:

1. Determinism over average speed. Worst-case is what matters.
2. Single address space. No page table switching, no TLB shootdown.
3. Fast path = zero allocation. Any malloc = unbounded jitter.
4. Interrupts reach threads directly. No generic framework, no dispatch, no accounting.
5. No global interrupt-disable or preemption-disable critical sections. Use priority masking.
6. Measurement infrastructure is first-class. Built with the kernel, not after.
