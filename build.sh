#!/bin/bash
set -e
cd '/mnt/e/Projects/AeroProjects/Aero OS Version/AeroOS 26R1'
rm -rf build kernel/src/main.o
mkdir -p build

CFLAGS='--target=riscv64-unknown-elf -march=rv64gc -mabi=lp64 -mcmodel=medany -nostdlib -ffreestanding -ffunction-sections -fdata-sections'
OBJS='build/boot.o build/trap.o build/uart.o build/clint.o build/phys.o build/heap.o build/syscall_shim.o build/userapp.o build/sched.o build/api.o build/kernel.o build/libc_stub.o build/libgcc_stub.o'

echo '=== 1. boot.S + trap.S ==='
clang $CFLAGS -c kernel/src/boot/riscv64/start.S -o build/boot.o
clang $CFLAGS -c kernel/src/boot/riscv64/trap.S -o build/trap.o

echo '=== 2. uart.c ==='
clang $CFLAGS -c kernel/src/driver/riscv64/uart.c -o build/uart.o

echo '=== 3. stubs ==='
clang --target=riscv64-unknown-elf -march=rv64gc -mabi=lp64 -mcmodel=medany -nostdlib -ffreestanding -c kernel/src/driver/riscv64/libc_stub.c -o build/libc_stub.o
clang --target=riscv64-unknown-elf -march=rv64gc -mabi=lp64 -mcmodel=medany -nostdlib -ffreestanding -c kernel/src/driver/riscv64/libgcc_stub.c -o build/libgcc_stub.o

echo '=== 3b. clint.c ==='
clang $CFLAGS -c kernel/src/driver/riscv64/clint.c -o build/clint.o

echo '=== 3c. mm/phys.c ==='
clang $CFLAGS -c kernel/src/mm/phys.c -o build/phys.o

echo '=== 3c2. mm/heap.c ==='
clang $CFLAGS -c kernel/src/mm/heap.c -o build/heap.o

echo '=== 3c2b. syscall_shim.S ==='
clang $CFLAGS -c kernel/src/syscall_shim.S -o build/syscall_shim.o

echo '=== 3c3. userapp.aero (Aero compiler) ==='
'/mnt/e/Projects/AeroProjects/Aero Lang Version/Aero 1.2.1---1.2.4/compiler/target/release/aero.exe' build kernel/src/userapp.aero --emit-obj --target riscv64-unknown-none
mv kernel/src/userapp.o build/userapp.o

echo '=== 3d. sched.c + api.c ==='
clang $CFLAGS -c kernel/src/sched.c -o build/sched.o
clang $CFLAGS -c kernel/src/api.c -o build/api.o

echo '=== 4. Aero main.aero ==='
'/mnt/e/Projects/AeroProjects/Aero Lang Version/Aero 1.2.1---1.2.4/compiler/target/release/aero.exe' build kernel/src/main.aero --emit-obj --target riscv64-unknown-none
mv kernel/src/main.o build/kernel.o

echo '=== 5. aero-ld (self-hosted RISC-V linker) ==='
export PATH="/root/.cargo/bin:$PATH"
AERO_LD='tools/aero-ld/target/release/aero-ld'
if [ ! -x "$AERO_LD" ]; then
    cargo build --release --manifest-path tools/aero-ld/Cargo.toml
fi
"$AERO_LD" -T target/riscv64-qemu-virt/linker.ld -o build/AeroOS.elf $OBJS

echo '=== BUILD OK ==='
ls -la build/AeroOS.elf

# 6. 规范化交付物文件名（26R1 发布标准）
echo '=== 6. Release packaging ==='
cp build/AeroOS.elf build/AeroOS-26R1-riscv64.elf
riscv64-linux-gnu-objcopy -O binary build/AeroOS.elf build/AeroOS-26R1-riscv64.bin

echo '=== BUILD OK ==='
ls -la build/AeroOS.elf build/AeroOS-26R1-riscv64.elf build/AeroOS-26R1-riscv64.bin
