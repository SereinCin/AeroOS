# AeroOS 26R1 — riscv64 QEMU virt build
#
# Build pipeline:
#   1. start.S → boot.o       (clang -c -target riscv64-unknown-elf)
#   2. main.aero → kernel.o   (aero build --emit-obj)
#   3. boot.o + kernel.o → AeroOS.elf  (ld.lld with linker.ld)
#   4. (optional) run in QEMU

TARGET  = riscv64-unknown-none
CC      = clang
AERO    = aero
LD      = ld.lld
QEMU    = qemu-system-riscv64

BOOT_SRC = kernel/src/boot/riscv64/start.S
BOOT_OBJ = build/boot.o
AERO_SRC = kernel/src/main.aero
AERO_OBJ = build/kernel.o
LINKER   = target/riscv64-qemu-virt/linker.ld
ELF      = build/AeroOS.elf

.PHONY: all clean run objdump

all: $(ELF)

$(BOOT_OBJ): $(BOOT_SRC) | build
	$(CC) -c -target riscv64-unknown-elf -march=rv64gc -mabi=lp64d \
	      -nostdlib -o $@ $<

$(AERO_OBJ): $(AERO_SRC) | build
	$(AERO) build $< --emit-obj --target $(TARGET) --output $@

$(ELF): $(BOOT_OBJ) $(AERO_OBJ) $(LINKER) | build
	$(LD) -T $(LINKER) -o $@ $(BOOT_OBJ) $(AERO_OBJ)

build:
	mkdir -p build

run: $(ELF)
	$(QEMU) -machine virt -bios none -kernel $(ELF) \
	        -nographic -serial mon:stdio

objdump: $(ELF)
	llvm-objdump -d -j .text.boot $(ELF) | head -40

clean:
	rm -rf build
