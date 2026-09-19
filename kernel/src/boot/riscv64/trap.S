# AeroOS 26R1 — RISC-V S-mode Trap Handler
#
# Full 29-register context frame for preemptive scheduling:
#   sp+0   = ra           sp+128 = s0          sp+224 = sepc
#   sp+8   = t0           sp+136 = s1
#   sp+16  = t1           sp+144 = s2           Frame size = 232 bytes
#   sp+24  = t2           sp+152 = s3           (29 regs × 8)
#   sp+32  = t3           sp+160 = s4
#   sp+40  = t4           sp+168 = s5
#   sp+48  = t5           sp+176 = s6
#   sp+56  = t6           sp+184 = s7
#   sp+64  = a0           sp+192 = s8
#   sp+72  = a1           sp+200 = s9
#   sp+80  = a2           sp+208 = s10
#   sp+88  = a3           sp+216 = s11
#   sp+96  = a4
#   sp+104 = a5
#   sp+112 = a6
#   sp+120 = a7
#
# On each trap we push this frame.  Timer interrupts additionally save the
# task's old sp into the scheduler, round-robin to the next runnable, then
# pop that next task's frame and sret into it.

.section .text.trap, "ax"
.global trap_handler
.type trap_handler, @function
.align 2

.equ CTX_SIZE, 232

trap_handler:
    # ---- push full context frame (232 B) ----
    addi    sp, sp, -CTX_SIZE
    sd      ra,    0(sp)
    sd      t0,    8(sp)
    sd      t1,   16(sp)
    sd      t2,   24(sp)
    sd      t3,   32(sp)
    sd      t4,   40(sp)
    sd      t5,   48(sp)
    sd      t6,   56(sp)
    sd      a0,   64(sp)
    sd      a1,   72(sp)
    sd      a2,   80(sp)
    sd      a3,   88(sp)
    sd      a4,   96(sp)
    sd      a5,  104(sp)
    sd      a6,  112(sp)
    sd      a7,  120(sp)
    sd      s0,  128(sp)
    sd      s1,  136(sp)
    sd      s2,  144(sp)
    sd      s3,  152(sp)
    sd      s4,  160(sp)
    sd      s5,  168(sp)
    sd      s6,  176(sp)
    sd      s7,  184(sp)
    sd      s8,  192(sp)
    sd      s9,  200(sp)
    sd      s10, 208(sp)
    sd      s11, 216(sp)
    csrr    t0, sepc
    sd      t0,  224(sp)

    # Read trap info
    csrr    t0, scause
    csrr    t1, sepc

    # Check: interrupt? (bit 63 set)
    srai    t2, t0, 63
    beqz    t2, trap_exception

    # Interrupt — supervisor timer interrupt = code 5
    andi    t2, t0, 0x3FF
    li      t3, 5
    bne     t2, t3, trap_unexpected

    # ================================================================
    # Timer interrupt path
    # ================================================================

    # 1. Re-arm timer via legacy SBI (absolute stime from S-mode `time` CSR)
    rdtime  a0
    li      a1, 2000000          # 0.2 s @ 10 MHz timebase
    add     a0, a0, a1
    li      a7, 0                # legacy SBI EID=0 (Set Timer)
    .word   0x00000073           # ecall

    # 2. Increment the boot/demo counter (kept for evidence)
    la      t0, timer_ticks
    ld      t1, 0(t0)
    addi    t1, t1, 1
    sd      t1, 0(t0)

    # 3. Save this task's frame BOTTOM (= sp after push) into scheduler.
    #    scheduler_tick() will advance to the next task and return ITS frame
    #    bottom; trap_return then pops that whole frame via sp+0..sp+224.
    la      t1, current_task
    ld      t2, 0(t1)
    beqz    t2, skip_reschedule  # scheduler not yet started (timer demo phase)
    sd      sp, 0(t2)            # current_task->saved_sp = frame bottom (= sp)

    # 4. Round-robin to next task; a0 comes back as its saved sp
    call    scheduler_tick

    # 5. Switch sp to the next task's saved sp (bottom of its frame)
    mv      sp, a0

skip_reschedule:
    j       trap_return

trap_exception:
trap_unexpected:
    # Debug dump: scause + sepc + stval as hex, then halt
    li      t3, 0x10000000       # UART0 THR
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
    # Restore full context frame (232 B), then sret
    ld      ra,    0(sp)
    ld      t0,    8(sp)
    ld      t1,   16(sp)
    ld      t2,   24(sp)
    ld      t3,   32(sp)
    ld      t4,   40(sp)
    ld      t5,   48(sp)
    ld      t6,   56(sp)
    ld      a0,   64(sp)
    ld      a1,   72(sp)
    ld      a2,   80(sp)
    ld      a3,   88(sp)
    ld      a4,   96(sp)
    ld      a5,  104(sp)
    ld      a6,  112(sp)
    ld      a7,  120(sp)
    ld      s0,  128(sp)
    ld      s1,  136(sp)
    ld      s2,  144(sp)
    ld      s3,  152(sp)
    ld      s4,  160(sp)
    ld      s5,  168(sp)
    ld      s6,  176(sp)
    ld      s7,  184(sp)
    ld      s8,  192(sp)
    ld      s9,  200(sp)
    ld      s10, 208(sp)
    ld      s11, 216(sp)
    ld      t0,  224(sp)
    csrw    sepc, t0
    addi    sp, sp, CTX_SIZE
    sret

    .size trap_handler, . - trap_handler

.extern timer_ticks
.extern current_task
.extern scheduler_tick
