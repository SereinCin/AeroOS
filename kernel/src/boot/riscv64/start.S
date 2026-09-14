# AeroOS 26R1 boot — riscv64 QEMU virt
# Bare-metal entry point. Loaded by QEMU at 0x80000000.
# Steps: set stack → clear BSS → call kernel_start() → halt on return.

.section .text.boot, "ax"
.global _start
_start:
    # Stack grows downward. Reserve 1MB at the top of RAM for kernel stack.
    # QEMU virt has 128MB RAM starting at 0x80000000.
    la      sp, _stack_top

    # Zero out BSS so .bss globals start as zero (Aero static mut relies on this).
    la      t0, _bss_start
    la      t1, _bss_end
.bss_loop:
    bge     t0, t1, .bss_done
    sd      zero, 0(t0)
    addi    t0, t0, 8
    j       .bss_loop
.bss_done:

    # Jump into Aero kernel. kernel_start() is the #[entry] function.
    call    kernel_start

    # If kernel ever returns — halt the CPU.
.halt:
    wfi
    j       .halt

# ---------------------------------------------------------------------------
# Stack space — 1MB, placed after all kernel sections so the pointer
# naturally ends up at the top when the linker fills .stack last.

.section .stack, "aw", @nobits
.align 12
_stack_bottom:
    .space  0x100000            # 1MB kernel stack
_stack_top:
