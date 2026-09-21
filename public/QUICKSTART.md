> **[中文版本 →](zh-CN/QUICKSTART.md)**

# Quickstart — Run AeroOS 26R1 in 10 minutes

## Prerequisites

| Tool | Purpose | Install (Ubuntu / WSL2) |
|---|---|---|
| clang 18+ / lld | C compilation + linking (integrated) | `wget -O - https://apt.llvm.org/llvm.sh \| sudo bash -s 22` |
| riscv64 binutils | Generate `.bin` (pure binary) | `sudo apt install -y binutils-riscv64-linux-gnu` |
| QEMU riscv64 | Run the kernel | `sudo apt install -y qemu-system-riscv64` |
| Rust / cargo | Build aero-ld (self-hosted linker) | `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \| sh` |
| Aero compiler 1.2.4 | Compile `.aero` → riscv64 object | `curl -fsSLO https://github.com/SereinCin/aero-lang/releases/download/v1.2.4/aero-v1.2.4-linux-x86_64.tar.gz && tar -xzf aero-v1.2.4-linux-x86_64.tar.gz && sudo cp bin/aero /usr/local/bin/` |

## One-command build

```bash
cd AeroOS-26R1
bash build.sh
```

Output:
```
build/AeroOS.elf                        # Raw linker output
build/AeroOS-26R1-riscv64.elf          # Canonical name — QEMU -kernel loads this directly (30 KB)
build/AeroOS-26R1-riscv64.bin          # Pure binary, for raw flash (8 KB)
```

## One-command run

```bash
./run-qemu.sh
# Ctrl-A X to exit QEMU
```

You should see:
```
OpenSBI v1.3                      ← Firmware banner (~30 lines)
...
AeroOS 26R1 booting...           ← Kernel boot banner
sched: 4 S-mode + 1 U-mode tasks created
T0: idle loop
T1: idle loop
T2: idle loop
T3: idle loop
hello from Aero                   ← U-mode userapp (Aero language!)
hello from Aero
... (continues, task-switches every 0.2s) ...
```

## One-command acceptance (P1.7)

```bash
# Boot test — 3s timeout, checks boot banner + no crash
./test-boot.sh
# → [PASS] boot banner printed
# → [PASS] no TRAP / panic / exception
# → [PASS] kernel running

# Interrupt test — 10s timeout, checks timer + U-mode syscalls
./test-interrupt.sh
# → [PASS] timer interrupt OK — 1300+ scheduler ticks
# → [PASS] all 4 S-mode tasks running: 4/4
# → [PASS] U-mode ecall OK — 50000+ syscalls
# → [PASS] zero TRAP / panic / exception
```

Both scripts exit with code 0 on all-PASS.

## What each output line means

| You see | What it is | Code |
|---|---|---|
| `OpenSBI v1.3` | OpenSBI FW_DYNAMIC firmware | QEMU default BIOS |
| `AeroOS 26R1 booting...` | Kernel boot banner | `kernel_start()` in `main.aero` |
| `T0` – `T3` | S-mode (kernel-space) worker tasks | `worker_0()` – `worker_3()` in `sched.c` |
| `hello from Aero` | U-mode (user-space) Aero-written program | `userapp_main()` in `kernel/src/userapp.aero` |

Tasks are round-robined by the 0.2s timer interrupt.

## Manual QEMU command

```bash
qemu-system-riscv64 \
    -machine virt \
    -bios default \
    -kernel build/AeroOS-26R1-riscv64.elf \
    -nographic \
    -monitor none
```

- `-machine virt` provides OpenSBI FW_DYNAMIC + CLINT MTIMER + NS16550 UART
- `-bios default` loads QEMU-bundled OpenSBI v1.3
- `-kernel` → OpenSBI FW_DYNAMIC reads the ELF, loads segments into RAM, jumps to ELF entry
- `-nographic` → UART output goes to terminal directly

## Troubleshooting

| Problem | Fix |
|---|---|
| `riscv64-linux-gnu-objcopy: command not found` | `sudo apt install -y binutils-riscv64-linux-gnu` |
| `clang: command not found` | Install LLVM 22 via apt.llvm.org (see Prerequisites) |
| `cargo: command not found` | Install Rust via rustup.rs |
| `aero: command not found` | Download `aero-v1.2.4-linux-x86_64.tar.gz` from GitHub releases, extract, put `bin/aero` on PATH |
| QEMU says `Could not load bios` | Old QEMU: replace `-bios default` with explicit path, e.g. `-bios /usr/share/qemu/opensbi-generic-fw_dynamic.bin` |
| No output after `OpenSBI v1.3` | Kernel panicked — run without `-monitor none` so you see the trap dump |
| Windows host? | Use WSL2 Ubuntu. This entire project is developed and built inside WSL2. |

## See also

- [ARCHITECTURE.md](ARCHITECTURE.md) — boot chain, trap flow, scheduler internals
- [HARDWARE.md](HARDWARE.md) — QEMU virt memory map, UART, CLINT, OpenSBI
- [WRITING-UMODE-APPS.md](WRITING-UMODE-APPS.md) — how to write your own Aero userland program
