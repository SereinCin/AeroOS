/* Linker script for AeroOS 26R1 — QEMU riscv64 virt
 *
 * OpenSBI (FW_DYNAMIC) loads at 0x80000000 (~261KB).
 * We place the kernel at 0x80200000, OpenSBI jumps here after boot.
 */

ENTRY(_start)

SECTIONS
{
    . = 0x80200000;

    .text.boot : { *(.text.boot) }
    .text      : { *(.text*) }
    .rodata    : { *(.rodata*) }
    .eh_frame  : { *(.eh_frame) }
    .data      : { *(.data*) }

    .bss (NOLOAD) : {
        _bss_start = .;
        *(.bss*) *(.sbss*)
        . = ALIGN(8);
        _bss_end = .;
    }

    .stack (NOLOAD) : {
        . = ALIGN(16);
        *(.stack)
        /* End of the resident kernel image; the physical frame allocator
         * manages everything above this, up to the device tree blob. */
        . = ALIGN(4096);
        _kernel_end = .;
    }

    /DISCARD/ : {
        *(.eh_frame_hdr) *(.comment) *(.note*)
    }
}
