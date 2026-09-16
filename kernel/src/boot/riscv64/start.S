# AeroOS 26R1 boot — riscv64 QEMU virt
#
# Boot sequence:
# 1. Set stack pointer
# 2. Clear BSS section
# 3. (Future) Set stvec, arm timer, enable S-mode interrupts
# 4. Call Aero kernel entry

.section .text.boot, "ax"
.global _start
_start:
    # --- Stack ---
    la      sp, _stack_top

    # --- BSS clear ---
    la      t0, _bss_start
    la      t1, _bss_end
.bss_loop:
    bge     t0, t1, .bss_done
    sd      zero, 0(t0)
    addi    t0, t0, 8
    j       .bss_loop
.bss_done:

    # --- Kernel entry ---
    call    kernel_start

.halt:
    wfi
    j       .halt

.section .stack, "aw", @nobits
.align 12
_stack_bottom:
    .space  0x100000
_stack_top: