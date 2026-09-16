// NS16550 UART driver for QEMU virt (AeroOS 26R1)
//
// QEMU virt machine has NS16550 at MMIO base 0x1000_0000.
// QEMU's NS16550 model accepts TX writes unconditionally — no need
// to poll LSR. We just write the byte and done.

#include <stdint.h>

#define UART_BASE   0x10000000ULL
#define UART_THR    0x00   // TX Holding Register (write)

static inline void uart_write_byte(uint8_t byte) {
    *(volatile uint8_t *)(UART_BASE + UART_THR) = byte;
}

void aeroos_uart_puts(const char *msg) {
    while (*msg) {
        uart_write_byte((uint8_t)*msg);
        msg++;
    }
}

void aeroos_uart_putc(char c) {
    uart_write_byte((uint8_t)c);
}
