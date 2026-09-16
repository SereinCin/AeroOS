#!/bin/bash
set -e
cd '/mnt/e/Projects/AeroProjects/Aero OS Version/AeroOS 26R1'
rm -rf build kernel/src/main.o
mkdir -p build

# Aero compiler (absolute WSL path to Windows exe)
AERO='/mnt/e/Projects/AeroProjects/Aero Lang Version/Aero 1.2.1---1.2.4/compiler/target/release/aero.exe'

echo '=== 1. boot.S ==='
clang --target=riscv64-unknown-elf -march=rv64gc -mabi=lp64 -nostdlib -ffreestanding -ffunction-sections -fdata-sections -c kernel/src/boot/riscv64/start.S -o build/boot.o

echo '=== 2. uart.c ==='
clang --target=riscv64-unknown-elf -march=rv64gc -mabi=lp64 -nostdlib -ffreestanding -ffunction-sections -fdata-sections -c kernel/src/driver/riscv64/uart.c -o build/uart.o

echo '=== 3-4. stubs ==='
clang --target=riscv64-unknown-elf -march=rv64gc -mabi=lp64 -nostdlib -ffreestanding -c kernel/src/driver/riscv64/libc_stub.c -o build/libc_stub.o
clang --target=riscv64-unknown-elf -march=rv64gc -mabi=lp64 -nostdlib -ffreestanding -c kernel/src/driver/riscv64/libgcc_stub.c -o build/libgcc_stub.o

echo '=== 5. Aero main.aero (section splitting fad395f) ==='
"$AERO" build kernel/src/main.aero --emit-obj --target riscv64-unknown-none
mv kernel/src/main.o build/kernel.o

echo '=== 6. ld.lld --gc-sections ==='
ld.lld --gc-sections -T target/riscv64-qemu-virt/linker.ld -o build/AeroOS.elf \
  build/boot.o build/uart.o build/kernel.o build/libc_stub.o build/libgcc_stub.o

echo ''
echo '=== BUILD OK ==='
ls -la build/AeroOS.elf

echo '=== Section scan on kernel.o ==='
readelf -S build/kernel.o 2>&1 | grep -E "name"
readelf -S build/kernel.o 2>&1 | grep -E "\\.text"
readelf -S build/kernel.o 2>&1 | grep -E "\\.data"

echo '=== ELF sections (linked) ==='
readelf -S build/AeroOS.elf 2>&1 | grep -E "name"
readelf -S build/AeroOS.elf 2>&1 | grep -E "\\.text|\\.data|\\.rodata"