/* Linker script for AeroOS 26R1 — QEMU riscv64 virt
 *
 * Memory layout of QEMU virt machine:
 *   0x1000_0000  MMIO (UART, virtio devices)
 *   0x8000_0000  128MB RAM  ← kernel loads here
 *
 * Placement strategy: boot code goes at the very start of RAM so that QEMU's
 * default boot entry (0x8000_0000 → _start) finds our entry point. Aero kernel
 * follows immediately after. Stack is placed at the end so it grows downward
 * into unused RAM.
 */

MEMORY
{
    RAM : ORIGIN = 0x80000000, LENGTH = 128M
}

ENTRY(_start)

SECTIONS
{
    . = ORIGIN(RAM);

    /* Boot assembly — must come first so _start is at 0x80000000 */
    .text.boot : {
        *(.text.boot)
    }

    /* Aero kernel code */
    .text : {
        *(.text*)
    }

    /* Read-only data (const strings, jump tables) */
    .rodata : {
        *(.rodata*)
    }

    /* Initialized global data (static mut with non-zero initializer) */
    .data : {
        *(.data*)
    }

    /* Zero-initialized globals. start.S clears this section before jumping
     * to Aero kernel so static mut variables start at 0. */
    .bss (NOLOAD) : {
        _bss_start = .;
        *(.bss*)
        . = ALIGN(8);
        _bss_end = .;
    }

    /* Kernel stack — 1MB, placed at end of kernel so stack pointer = top */
    .stack (NOLOAD) : {
        . = ALIGN(16);
        *(.stack)
    }
}
