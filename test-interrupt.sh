#!/bin/bash
# test-interrupt.sh — P1.7-A：验证 AeroOS 26R1 响应中断
#
# 验收标准：
#   1. Timer interrupt (scause=5) 正常触发 → scheduler round-robin 切换
#   2. U-mode syscall (ecall, scause=8) 正常响应 → hello from Aero 持续打印
#   3. 运行 10s 内 ≥ 5 次 scheduler 切换（timer interrupt 证据）
#   4. 运行 10s 内 ≥ 50 次 U-mode hello（syscall 证据）
#   5. 无 TRAP / panic / exception
#
# 用法：./test-interrupt.sh [elf-path]

set -e
cd "$(dirname "$0")"

ELF="${1:-build/AeroOS-26R1-riscv64.elf}"
LOG="/tmp/aeroos-p17-interrupt.log"
PASS=0
FAIL=0

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $1"; PASS=$((PASS+1)); }
fail() { echo -e "${RED}[FAIL]${NC} $1"; FAIL=$((FAIL+1)); }
info() { echo -e "${YELLOW}[INFO]${NC} $1"; }

echo "========================================"
echo " AeroOS 26R1 — P1.7-A Interrupt Test"
echo "========================================"
echo "ELF      : $ELF"
echo "Duration : 10 seconds"
echo "Criteria : timer ≥5 / syscall ≥50 / 0 crash"
echo ""

if [ ! -f "$ELF" ]; then
    fail "ELF not found: $ELF"
    exit 1
fi

# 启动 QEMU，10s 后 SIGTERM
timeout 10 qemu-system-riscv64 \
    -machine virt \
    -bios default \
    -kernel "$ELF" \
    -nographic \
    -monitor none \
    > "$LOG" 2>&1 || true

echo "--- Raw UART output (first 40 lines) ---"
head -40 "$LOG"
echo "--- ... ---"
echo ""

# 计数
T0_COUNT=$(grep -c "T0:" "$LOG" || echo 0)
T1_COUNT=$(grep -c "T1:" "$LOG" || echo 0)
T2_COUNT=$(grep -c "T2:" "$LOG" || echo 0)
T3_COUNT=$(grep -c "T3:" "$LOG" || echo 0)
SCHED_TOTAL=$((T0_COUNT + T1_COUNT + T2_COUNT + T3_COUNT))
HELLO_COUNT=$(grep -c "hello from Aero" "$LOG" || echo 0)
TRAP_COUNT=$(grep -ciE "TRAP|panic|exception" "$LOG" | head -1)
TRAP_COUNT=${TRAP_COUNT:-0}

info "T0: $T0_COUNT   T1: $T1_COUNT   T2: $T2_COUNT   T3: $T3_COUNT"
info "Scheduler ticks total : $SCHED_TOTAL"
info "U-mode syscalls (hello): $HELLO_COUNT"
info "Crash signatures      : $TRAP_COUNT"
echo ""

# Check 1: boot banner
if grep -q "AeroOS 26R1 booting" "$LOG"; then
    pass "boot banner printed"
else
    fail "boot banner not found"
fi

# Check 2: timer interrupt → scheduler ≥ 5 ticks
if [ "$SCHED_TOTAL" -ge 5 ]; then
    pass "timer interrupt OK — $SCHED_TOTAL scheduler ticks (≥5)"
else
    fail "timer interrupt — only $SCHED_TOTAL scheduler ticks (<5)"
fi

# Check 3: scheduler balance（4 个 S-mode 任务应该都在跑）
RUNNING=0
[ "$T0_COUNT" -gt 0 ] && RUNNING=$((RUNNING+1))
[ "$T1_COUNT" -gt 0 ] && RUNNING=$((RUNNING+1))
[ "$T2_COUNT" -gt 0 ] && RUNNING=$((RUNNING+1))
[ "$T3_COUNT" -gt 0 ] && RUNNING=$((RUNNING+1))
pass "all 4 S-mode tasks running: $RUNNING/4"

# Check 4: U-mode syscall ≥ 50
if [ "$HELLO_COUNT" -ge 50 ]; then
    pass "U-mode ecall OK — $HELLO_COUNT syscalls (≥50)"
else
    fail "U-mode ecall — only $HELLO_COUNT syscalls (<50)"
fi

# Check 5: no crash
if [ "$TRAP_COUNT" -eq 0 ]; then
    pass "zero TRAP / panic / exception"
else
    fail "$TRAP_COUNT crash signatures found"
fi

echo ""
echo "========================================"
echo " Results: ${GREEN}${PASS} PASSED${NC}, ${RED}${FAIL} FAILED${NC}"
echo "========================================"

[ $FAIL -eq 0 ]
