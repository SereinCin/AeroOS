#!/bin/bash
# run-qemu.sh — 一键在 QEMU riscv64 virt 中启动 AeroOS 26R1
#
# 用法：
#   ./run-qemu.sh              # 用最新 build 产物
#   ./run-qemu.sh path/to.elf  # 指定 ELF
#
# Ctrl-A X 退出 QEMU

set -e
cd "$(dirname "$0")"

ELF="${1:-build/AeroOS-26R1-riscv64.elf}"

if [ ! -f "$ELF" ]; then
    echo "ERROR: ELF not found: $ELF"
    echo "Run ./build.sh first, or pass the path as argument."
    exit 1
fi

QEMU_BIN="qemu-system-riscv64"
if ! command -v "$QEMU_BIN" >/dev/null 2>&1; then
    echo "ERROR: $QEMU_BIN not found. Install: sudo apt install qemu-system-riscv64"
    exit 1
fi

echo "=== AeroOS 26R1 QEMU run ==="
echo "ELF : $ELF"
echo "Press Ctrl-A X to exit QEMU."
echo ""

exec qemu-system-riscv64 \
    -machine virt \
    -bios default \
    -kernel "$ELF" \
    -nographic \
    -monitor none
