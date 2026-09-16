# AeroOS 26R1 — RISC-V S-mode Trap Handler (debug version)
# Prints scause + sepc to UART on unexpected traps.

.section .text.trap, "ax"
.global trap_handler
.type trap_handler, @function

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

    # === Timer interrupt: rdtime + SBI set_timer ===
    li a0, 1000000; li a7, 0; .word 0x00000073

    # Increment timer_ticks
    la      t0, timer_ticks
    ld      t1, 0(t0)
    addi    t1, t1, 1
    sd      t1, 0(t0)

    j       trap_return

trap_exception:
trap_unexpected:
    # Debug: dump scause low 8 bits + sepc low 8 bits
    # Print header chars via UART
    li      t3, 0x10000000      # UART0 THR
    li      t4, '!'
    sb      t4, 0(t3)
    li      t4, 'X'
    sb      t4, 0(t3)
    li      t4, ':'
    sb      t4, 0(t3)
    # Print scause lower byte as hex (but printable as char 32-126)
    # Just print low byte as digit
    andi    t4, t0, 0xFF
    call    print_hex_byte
    li      t4, ' '
    sb      t4, 0(t3)
    li      t4, 'S'
    sb      t4, 0(t3)
    li      t4, 'E'
    sb      t4, 0(t3)
    li      t4, 'P'
    sb      t4, 0(t3)
    li      t4, '='
    sb      t4, 0(t3)
    andi    t4, t1, 0xFF
    call    print_hex_byte
    li      t4, '\n'
    sb      t4, 0(t3)

trap_halt:
    wfi
    j       trap_halt

print_hex_byte:
    # Print low byte of t4 as 2-digit hex to UART (uses t3, t4, t5)
    li      t3, 0x10000000
    srli    t5, t4, 4
    li      a0, 10
    blt     t5, a0, 1f
    addi    t5, t5, 'A'-10
    j       2f
1:  addi    t5, t5, '0'
2:  sb      t5, 0(t3)
    andi    t5, t4, 0xF
    blt     t5, a0, 3f
    addi    t5, t5, 'A'-10
    j       4f
3:  addi    t5, t5, '0'
4:  sb      t5, 0(t3)
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