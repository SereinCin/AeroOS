# AeroOS 26R1 — RISC-V S-mode Trap Handler (debug version)
# Prints scause + sepc to UART on unexpected traps.

.section .text.trap, "ax"
.global trap_handler
.type trap_handler, @function
.align 2

trap_handler:
    # Save all caller-saved registers
    addi    sp, sp, -128
    sd      ra,   0(sp)
    sd      t0,   8(sp)
    sd      t1,  16(sp)
    sd      t2,  24(sp)
    sd      t3,  32(sp)
    sd      t4,  40(sp)
    sd      t5,  48(sp)
    sd      t6,  56(sp)
    sd      a0,  64(sp)
    sd      a1,  72(sp)
    sd      a2,  80(sp)
    sd      a3,  88(sp)
    sd      a4,  96(sp)
    sd      a5, 104(sp)
    sd      a6, 112(sp)
    sd      a7, 120(sp)

    # Read trap info
    csrr    t0, scause
    csrr    t1, sepc

    # Check: interrupt? (bit 63 set)
    srai    t2, t0, 63
    beqz    t2, trap_exception

    # Interrupt — check code
    andi    t2, t0, 0x3FF
    li      t3, 5               # supervisor timer interrupt
    bne     t2, t3, trap_unexpected

    # === Timer interrupt: reschedule via legacy SBI set_timer (EID=0) ===
    # SBI set_timer wants an ABSOLUTE stime.  The CLINT's mtimecmp is
    # M-mode only (S-mode MMIO there faults), so read the S-mode `time`
    # CSR and add the interval, then trap into OpenSBI.
    rdtime  a0
    li      a1, 2000000         # 0.2 s @ 10 MHz timebase
    add     a0, a0, a1
    li      a7, 0               # legacy SBI EID=0 (Set Timer)
    .word   0x00000073          # ecall

    # Increment timer_ticks
    la      t0, timer_ticks
    ld      t1, 0(t0)
    addi    t1, t1, 1
    sd      t1, 0(t0)

    j       trap_return

trap_exception:
trap_unexpected:
    # Debug: dump full 64-bit scause + sepc as hex, then halt.
    li      t3, 0x10000000      # UART0 THR
    li      t4, '\n'
    sb      t4, 0(t3)
    li      t4, 'T'
    sb      t4, 0(t3)
    li      t4, 'R'
    sb      t4, 0(t3)
    li      t4, 'A'
    sb      t4, 0(t3)
    li      t4, 'P'
    sb      t4, 0(t3)
    li      t4, ' '
    sb      t4, 0(t3)
    li      t4, 'c'
    sb      t4, 0(t3)
    li      t4, 'a'
    sb      t4, 0(t3)
    li      t4, 'u'
    sb      t4, 0(t3)
    li      t4, 's'
    sb      t4, 0(t3)
    li      t4, 'e'
    sb      t4, 0(t3)
    li      t4, '='
    sb      t4, 0(t3)
    csrr    a1, scause
    call    print_hex64
    li      t4, ' '
    sb      t4, 0(t3)
    li      t4, 's'
    sb      t4, 0(t3)
    li      t4, 'e'
    sb      t4, 0(t3)
    li      t4, 'p'
    sb      t4, 0(t3)
    li      t4, 'c'
    sb      t4, 0(t3)
    li      t4, '='
    sb      t4, 0(t3)
    csrr    a1, sepc
    call    print_hex64
    li      t4, ' '
    sb      t4, 0(t3)
    li      t4, 's'
    sb      t4, 0(t3)
    li      t4, 't'
    sb      t4, 0(t3)
    li      t4, 'v'
    sb      t4, 0(t3)
    li      t4, 'a'
    sb      t4, 0(t3)
    li      t4, 'l'
    sb      t4, 0(t3)
    li      t4, '='
    sb      t4, 0(t3)
    csrr    a1, stval
    call    print_hex64
    li      t4, '\n'
    sb      t4, 0(t3)

trap_halt:
    wfi
    j       trap_halt

print_hex64:
    # Print a1 as 16 hex digits. Clobbers a1, t3, t4, t5, t6.
    li      t3, 0x10000000
    li      t6, 60
5:  srl     t5, a1, t6
    andi    t5, t5, 0xF
    li      t4, 10
    blt     t5, t4, 6f
    addi    t5, t5, 'A'-10
    j       7f
6:  addi    t5, t5, '0'
7:  sb      t5, 0(t3)
    addi    t6, t6, -4
    bgez    t6, 5b
    ret

trap_return:
    # Restore saved registers
    ld      ra,   0(sp)
    ld      t0,   8(sp)
    ld      t1,  16(sp)
    ld      t2,  24(sp)
    ld      t3,  32(sp)
    ld      t4,  40(sp)
    ld      t5,  48(sp)
    ld      t6,  56(sp)
    ld      a0,  64(sp)
    ld      a1,  72(sp)
    ld      a2,  80(sp)
    ld      a3,  88(sp)
    ld      a4,  96(sp)
    ld      a5, 104(sp)
    ld      a6, 112(sp)
    ld      a7, 120(sp)
    addi    sp, sp, 128

    sret

    .size trap_handler, . - trap_handler

.extern timer_ticks