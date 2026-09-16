# AeroOS 26R1 boot — riscv64 QEMU virt

.section .text.boot, "ax"
.global _start
_start:
    la      sp, _stack_top

    la      t0, _bss_start
    la      t1, _bss_end
.bss_loop:
    bge     t0, t1, .bss_done
    sd      zero, 0(t0)
    addi    t0, t0, 8
    j       .bss_loop
.bss_done:

    call    kernel_start

.halt:
    wfi
    j       .halt

.section .stack, "aw", @nobits
.align 12
_stack_bottom:
    .space  0x100000
_stack_top:
