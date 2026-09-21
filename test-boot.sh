#!/bin/bash
# test-boot.sh — P1.7-A：验证 AeroOS 26R1 在 QEMU 中成功启动并打印预期信息
#
# 验收标准：
#   1. UART 输出包含 "AeroOS 26R1 booting"
#   2. 进程正常退出（timeout 10s 后 SIGTERM）
#   3. 不出现 TRAP / panic / exception
#
# 用法：./test-boot.sh [elf-path]

set -e
cd "$(dirname "$0")"

ELF="${1:-build/AeroOS-26R1-riscv64.elf}"
LOG="/tmp/aeroos-p17-boot.log"
PASS=0
FAIL=0

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $1"; PASS=$((PASS+1)); }
fail() { echo -e "${RED}[FAIL]${NC} $1"; FAIL=$((FAIL+1)); }

echo "========================================"
echo " AeroOS 26R1 — P1.7-A QEMU Boot Test"
echo "========================================"
echo "ELF : $ELF"
echo ""

# 检查 ELF 存在
if [ ! -f "$ELF" ]; then
    fail "ELF not found: $ELF"
    exit 1
fi

# 启动 QEMU，timeout 10s 后杀掉
timeout 10 qemu-system-riscv64 \
    -machine virt \
    -bios default \
    -kernel "$ELF" \
    -nographic \
    -monitor none \
    > "$LOG" 2>&1 || true

echo "--- QEMU UART output ---"
cat "$LOG"
echo "------------------------"
echo ""

# Check 1: boot banner
if grep -q "AeroOS 26R1 booting" "$LOG"; then
    pass "boot banner 'AeroOS 26R1 booting' printed"
else
    fail "boot banner not found"
fi

# Check 2: no TRAP / panic / exception
if grep -qiE "TRAP|panic|exception|ERROR|abort" "$LOG"; then
    fail "TRAP/panic/exception detected"
    echo "  matches:"
    grep -iE "TRAP|panic|exception|ERROR|abort" "$LOG" | head -5
else
    pass "no TRAP / panic / exception"
fi

# Check 3: 系统在持续运行（有周期性输出）
if grep -q "hello from Aero" "$LOG" || grep -qE "T[0-4]:" "$LOG"; then
    pass "kernel running (U-mode or scheduler output present)"
else
    fail "kernel does not appear to be running"
fi

echo ""
echo "========================================"
echo " Results: ${GREEN}${PASS} PASSED${NC}, ${RED}${FAIL} FAILED${NC}"
echo "========================================"

[ $FAIL -eq 0 ]
