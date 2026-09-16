# AeroOS 26R1 — riscv64 QEMU virt build
# Run from repo root:  make -C target/riscv64-qemu-virt

TARGET   = riscv64-unknown-none
CC       = clang
AERO     = aero
LD       = ld.lld
QEMU     = qemu-system-riscv64

# Uniform abi across all objects — no hardware float, softfloat only
CFLAGS  = -target riscv64-unknown-elf -march=rv64gc -mabi=lp64 \
          -nostdlib -ffreestanding \
          -ffunction-sections -fdata-sections \
          -fno-unwind-tables -fno-asynchronous-unwind-tables
LDFLAGS = --gc-sections

.PHONY: all clean run objdump nm
all: build/AeroOS.elf

build:
	mkdir -p build

build/boot.o: ../../kernel/src/boot/riscv64/start.S | build
	$(CC) -c $(CFLAGS) -o $@ $<

build/uart.o: ../../kernel/src/driver/riscv64/uart.c | build
	$(CC) -c $(CFLAGS) -o $@ $<

build/libc_stub.o: ../../kernel/src/driver/riscv64/libc_stub.c | build
	$(CC) -c $(CFLAGS) -o $@ $<

build/libgcc_stub.o: ../../kernel/src/driver/riscv64/libgcc_stub.c | build
	$(CC) -c $(CFLAGS) -o $@ $<

build/kernel.o: ../../kernel/src/main.aero | build
	$(AERO) build $< --emit-obj --target $(TARGET)
	mv ../../kernel/src/main.o build/kernel.o

build/AeroOS.elf: build/boot.o build/uart.o build/kernel.o build/libc_stub.o build/libgcc_stub.o linker.ld
	$(LD) $(LDFLAGS) -T linker.ld -o $@ \
	    build/boot.o build/uart.o build/kernel.o build/libc_stub.o build/libgcc_stub.o

run: build/AeroOS.elf
	$(QEMU) -machine virt -nographic -monitor none -kernel $<

objdump: build/AeroOS.elf
	llvm-objdump -d -j .text.boot $< 2>&1 | head -30

nm: build/AeroOS.elf
	llvm-nm build/AeroOS.elf 2>&1 | grep -E " T | _start|kernel_start"

clean:
	rm -rf build ../../kernel/src/main.o ../../kernel/src/*.o
