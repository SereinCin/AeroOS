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

## Development Methodology

AeroOS 26R1 uses a hybrid workflow. AI assistance is used for mechanical,
repetitive tasks, but all core design and implementation decisions are
human-authored and reviewed.

### Manually authored (~90% of the work)
- Kernel architecture: single-address-space S-mode design rationale
- Trap frame layout (30 registers, 240 bytes) and ecall dispatch contract
- Preemptive round-robin scheduler logic and timer gate (STIE + SIE)
- Memory map: OpenSBI FW_DYNAMIC handoff at 0x80200000
- Syscall ABI: a7-based dispatch with 4 syscalls (write / yield / exit / fork)
- Aero-binding shim design for U-mode task calling convention
- 26 / 27 dual-line versioning model and T-patch vs EVT classification

### AI-assisted (~10% of the work, mechanical only)
- UART0 NS16550 register table lookup and bit-field configuration
- CLINT MTIMER divider math validation (10 MHz base to 0.2 s tick)
- Initial CI workflow YAML scaffolding
- Release script and GitHub REST API integration boilerplate
- Documentation first-draft (manually reviewed and rewritten)
- Repetitive refactoring (rename local variable across 3 files)

All AI-generated code passes manual review before commit. AI suggestions
are rejected when they violate project constraints: single address space,
zero-allocation fast path, no global interrupt-disable critical sections.
Commit messages, design documents, and versioning policy are written
entirely by the team.

### About the history timeline

The public git history shows commits from September 2026 through the
release date. Most active development happened in a private repository
earlier in the year; this public repository tracks the cleaned, reviewed
code leading to the 26R1 pre-release. Individual commit timestamps
reflect review and integration cadence, not original coding pace.
