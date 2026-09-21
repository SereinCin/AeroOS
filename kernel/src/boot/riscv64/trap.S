# AeroOS 26R1 — RISC-V S-mode Trap Handler
#
# Full 30-register context frame for preemptive scheduling + U-mode ecall:
#   sp+0   = ra           sp+128 = s0          sp+224 = sepc
#   sp+8   = t0           sp+136 = s1          sp+232 = sstatus  ← NEW
#   sp+16  = t1           sp+144 = s2          Frame size = 240 bytes
#   sp+24  = t2           sp+152 = s3          (30 regs × 8)
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
# sepc (frame[28])  : trap return PC; ecall path adds 4 before writing back
# sstatus (frame[29]): saved SPP/SPIE; controls whether sret lands in U or S

.section .text.trap, "ax"
.global trap_handler
.type trap_handler, @function
.align 2

.equ CTX_SIZE, 240

trap_handler:
    # ---- push full context frame (240 B) ----
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
    csrr    t0, sstatus
    sd      t0,  232(sp)

    # Read trap info
    csrr    t0, scause
    csrr    t1, sepc

    # Check: interrupt? (bit 63 set)
    srai    t2, t0, 63
    beqz    t2, trap_exception

    # ---------------------------------------------------------------
    # Interrupt — supervisor timer interrupt = code 5
    # ---------------------------------------------------------------
    andi    t2, t0, 0x3FF
    li      t3, 5
    bne     t2, t3, trap_unexpected

    # 1. Re-arm timer via legacy SBI
    rdtime  a0
    li      a1, 2000000          # 0.2 s @ 10 MHz timebase
    add     a0, a0, a1
    li      a7, 0                # legacy SBI EID=0 (Set Timer)
    .word   0x00000073           # ecall

    # 2. Increment tick counter (for debug/statistics only)
    la      t0, timer_ticks
    ld      t1, 0(t0)
    addi    t1, t1, 1
    sd      t1, 0(t0)

    # 3. Save this task's frame BOTTOM (= sp after push) into scheduler.
    la      t1, current_task
    ld      t2, 0(t1)
    beqz    t2, skip_reschedule  # scheduler not yet started
    sd      sp, 0(t2)            # current_task->saved_sp = frame bottom

    # 4. Round-robin to next task
    call    scheduler_tick

    # 5. Switch sp to the next task's saved sp
    mv      sp, a0

skip_reschedule:
    j       trap_return

trap_exception:
    # Check: supervisor env call from U-mode (scause code 8)
    andi    t2, t0, 0x3FF
    li      t3, 8
    beq     t2, t3, trap_ecall

trap_unexpected:
    # Debug dump
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

# -----------------------------------------------------------------------
# ECALL from U-mode (scause code 8)
#   a7 = syscall number, a0/a1 = args
#   We modify a0 (return value) and increment sepc by 4 to skip ecall.
# -----------------------------------------------------------------------
trap_ecall:
    # sepc += 4 (skip the ecall instruction we just executed)
    ld      t0, 224(sp)
    addi    t0, t0, 4
    sd      t0, 224(sp)

    # Dispatch by a7
    ld      a7, 120(sp)
    li      t0, 1                              # SYS_write
    beq     a7, t0, ecall_write
    li      t0, 2                              # SYS_yield
    beq     a7, t0, ecall_yield
    li      t0, 3                              # SYS_fork
    beq     a7, t0, ecall_fork
    li      t0, 4                              # SYS_exit
    beq     a7, t0, ecall_exit
    # Unknown syscall — return -1
    li      a0, -1
    sd      a0, 64(sp)
    j       ecall_return

ecall_write:
    # a0 = str ptr, a1 = len  (already in a0/a1 from frame[8]/frame[9])
    ld      a0, 64(sp)                         # a0 = str
    ld      a1, 72(sp)                         # a1 = len
    call    aeroos_sys_write
    sd      a0, 64(sp)                         # return value back into a0 slot
    j       ecall_return

ecall_yield:
    call    scheduler_advance
    # Return 0
    li      a0, 0
    sd      a0, 64(sp)
    # Trigger a timer interrupt immediately — set timer to "now + small"
    rdtime  a0
    li      a1, 50000
    add     a0, a0, a1
    li      a7, 0
    .word   0x00000073
    j       ecall_return

ecall_fork:
    # a0 = entry function ptr
    ld      a0, 64(sp)
    call    aeroos_sys_fork
    sd      a0, 64(sp)                         # return slot index (>=0) or -1
    j       ecall_return

ecall_exit:
    # U-mode task is done — just hang it here (set saved_sp = 0 so scheduler skips it later)
    # For MVP we simply spin; the task will still be round-robin'd into but does nothing.
    j       ecall_exit_loop
ecall_exit_loop:
    # Re-arm timer to keep other tasks alive, then wait
    rdtime  a0
    li      a1, 2000000
    add     a0, a0, a1
    li      a7, 0
    .word   0x00000073
    # Then do wfi loop — but we're still in S-mode here. Just busy loop.
    j       ecall_exit_loop

ecall_return:
    j       trap_return

trap_return:
    # Restore sstatus first (so SPP is set correctly for sret), then sepc.
    # FORCE SPIE=1: hardware trap entry always clears SPIE (moves old SIE
    # into it, then zeros SPIE to prevent re-entrant traps).  If we blindly
    # restore it, sret sets SIE=SPIE=0 and interrupts are OFF forever.
    ld      t0, 232(sp)
    ori     t0, t0, 0x20            # SPIE (bit 5) = 1
    csrw    sstatus, t0
    ld      t0, 224(sp)
    csrw    sepc, t0
    # Restore all GPRs
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
    addi    sp, sp, CTX_SIZE
    sret

    .size trap_handler, . - trap_handler

.extern timer_ticks
.extern current_task
.extern scheduler_tick
.extern scheduler_advance
.extern aeroos_sys_write
.extern aeroos_sys_fork
