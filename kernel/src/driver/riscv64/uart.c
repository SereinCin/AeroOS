// NS16550 UART driver for QEMU virt (AeroOS 26R1)
//
// QEMU virt machine has a single NS16550-compatible UART at MMIO base
// 0x1000_0000 (machine "virt" board). All registers are 8-bit at
// 4-byte stride offsets. We only use TX to print boot messages — RX
// comes later when we need a shell.

#include <stdint.h>

#define UART_BASE   0x10000000ULL

// Register offsets (byte-addressed, but accessed as i32 via volatile_load/store)
#define UART_THR    0x00   // Transmit Holding Register  (write)
#define UART_LSR    0x05   // Line Status Register       (read)
                            //   bit 5 = Transmitter Holding Register Empty

// Write a single byte to the UART. Blocks until TX FIFO is ready.
static inline void uart_write_byte(uint8_t byte) {
    volatile uint32_t *thr = (volatile uint32_t *)(UART_BASE + UART_THR);
    volatile uint32_t *lsr = (volatile uint32_t *)(UART_BASE + UART_LSR);

    while (!(*lsr & 0x20)) { }   // Wait until TX FIFO empty
    *thr = byte;
}

// Print a C string to the UART, byte by byte.
void aeroos_uart_puts(const char *msg) {
    while (*msg) {
        uart_write_byte((uint8_t)*msg);
        msg++;
    }
}

// Print a single character — kept separate for Aero convenience.
void aeroos_uart_putc(char c) {
    uart_write_byte((uint8_t)c);
}
