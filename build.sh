#!/bin/bash
set -e
cd '/mnt/e/Projects/AeroProjects/Aero OS Version/AeroOS 26R1'
rm -rf build kernel/src/main.o
mkdir -p build

echo '=== 1. boot.S + trap.S ==='
clang --target=riscv64-unknown-elf -march=rv64gc -mabi=lp64 -nostdlib -ffreestanding -ffunction-sections -fdata-sections -c kernel/src/boot/riscv64/start.S -o build/boot.o
clang --target=riscv64-unknown-elf -march=rv64gc -mabi=lp64 -nostdlib -ffreestanding -ffunction-sections -fdata-sections -c kernel/src/boot/riscv64/trap.S -o build/trap.o

echo '=== 2. uart.c ==='
clang --target=riscv64-unknown-elf -march=rv64gc -mabi=lp64 -nostdlib -ffreestanding -ffunction-sections -fdata-sections -c kernel/src/driver/riscv64/uart.c -o build/uart.o

echo '=== 3. stubs ==='
clang --target=riscv64-unknown-elf -march=rv64gc -mabi=lp64 -nostdlib -ffreestanding -c kernel/src/driver/riscv64/libc_stub.c -o build/libc_stub.o
clang --target=riscv64-unknown-elf -march=rv64gc -mabi=lp64 -nostdlib -ffreestanding -c kernel/src/driver/riscv64/libgcc_stub.c -o build/libgcc_stub.o

echo '=== 3b. clint.c ==='
clang --target=riscv64-unknown-elf -march=rv64gc -mabi=lp64 -nostdlib -ffreestanding -ffunction-sections -fdata-sections -c kernel/src/driver/riscv64/clint.c -o build/clint.o

echo '=== 4. Aero main.aero ==='
'/mnt/e/Projects/AeroProjects/Aero Lang Version/Aero 1.2.1---1.2.4/compiler/target/release/aero.exe' build kernel/src/main.aero --emit-obj --target riscv64-unknown-none
mv kernel/src/main.o build/kernel.o

echo '=== 5. ld.lld --gc-sections ==='
ld.lld --gc-sections -T target/riscv64-qemu-virt/linker.ld -o build/AeroOS.elf build/boot.o build/trap.o build/uart.o build/clint.o build/kernel.o build/libc_stub.o build/libgcc_stub.o

echo '=== BUILD OK ==='
ls -la build/AeroOS.elf
echo '--- nm ---'
llvm-nm build/AeroOS.elf 2>&1 | grep -E \"timer|trap|kernel_start\"