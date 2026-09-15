# AeroOS 26R1 — riscv64 QEMU virt build
#
# Build pipeline:
#   1. start.S → boot.o       (clang)
#   2. uart.c  → uart.o       (clang -nostdlib, NS16550 MMIO helpers)
#   3. main.aero → kernel.o   (aero build --emit-obj)
#   4. all .o  → AeroOS.elf   (ld.lld with custom linker script)
#   5. run in QEMU virt

TARGET  = riscv64-unknown-none
CC      = clang
AERO    = aero
LD      = ld.lld
QEMU    = qemu-system-riscv64

BOOT_SRC = kernel/src/boot/riscv64/start.S
UART_SRC = kernel/src/driver/riscv64/uart.c
AERO_SRC = kernel/src/main.aero
LINKER   = target/riscv64-qemu-virt/linker.ld

ELF      = build/AeroOS.elf
BOOT_OBJ = build/boot.o
UART_OBJ = build/uart.o
AERO_OBJ = build/kernel.o

.PHONY: all clean run objdump

all: $(ELF)

# Pure assembly boot entry
$(BOOT_OBJ): $(BOOT_SRC) | build
	$(CC) -c -target riscv64-unknown-elf -march=rv64gc -mabi=lp64d \
	      -nostdlib -o $@ $<

# NS16550 MMIO helpers — plain C, no libc needed
$(UART_OBJ): $(UART_SRC) | build
	$(CC) -c -target riscv64-unknown-elf -march=rv64gc -mabi=lp64d \
	      -nostdlib -ffreestanding -o $@ $<

# Aero kernel entry → riscv64 freestanding .o
$(AERO_OBJ): $(AERO_SRC) | build
	$(AERO) build $< --emit-obj --target $(TARGET)

# Link all pieces into flat ELF
$(ELF): $(BOOT_OBJ) $(UART_OBJ) $(AERO_OBJ) $(LINKER) | build
	$(LD) -T $(LINKER) -o $@ $^

build:
	mkdir -p build

run: $(ELF)
	$(QEMU) -machine virt -bios none -kernel $(ELF) \
	        -nographic -serial mon:stdio

objdump: $(ELF)
	llvm-objdump -d -j .text.boot $(ELF) | head -40

clean:
	rm -rf build
