#!/bin/bash
# release.sh — AeroOS 26R1 公开发布包打包
#
# 生成两个 zip：
#   aeroos-26r1-riscv64-qemu.zip    # 公开包（运行时需要）
#   aeroos-26r1-source.zip          # 公开包（源码）
#
# 用法：bash release.sh

set -e
cd "$(dirname "$0")"

VERSION="26R1"
RELNAME="aeroos-26r1"
RELEASE_DIR="release"
rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

# ---------------------------------------------------------------------------
# 1. 运行时包（用户拿到就能跑）
# ---------------------------------------------------------------------------
echo "=== 1. 运行时包 ==="
RUN="$RELEASE_DIR/${RELNAME}-riscv64-qemu"
mkdir -p "$RUN"

# 可启动镜像
cp build/AeroOS-26R1-riscv64.elf "$RUN/"
cp build/AeroOS-26R1-riscv64.bin "$RUN/"

# 运行验证套件
cp run-qemu.sh "$RUN/"
cp test-boot.sh "$RUN/"
cp test-interrupt.sh "$RUN/"
chmod +x "$RUN"/*.sh

# 文档（只放用户需要的）
cp README.md "$RUN/README.md"
cp docs/RUN.md "$RUN/RUN.md"
cp docs/P1-验收报告.md "$RUN/P1-验收报告.md"
cp docs/CHANGELOG.md "$RUN/CHANGELOG.md"
cp -r public "$RUN/public"

( cd "$RELEASE_DIR" && zip -r "${RELNAME}-riscv64-qemu.zip" "${RELNAME}-riscv64-qemu" )
rm -rf "$RUN"
echo "    → ${RELNAME}-riscv64-qemu.zip"

# ---------------------------------------------------------------------------
# 2. 源码包（带编译器工具链）
# ---------------------------------------------------------------------------
echo "=== 2. 源码 + 工具链包 ==="
SRC="$RELEASE_DIR/${RELNAME}-source"
mkdir -p "$SRC/kernel/src/boot/riscv64" "$SRC/kernel/src/driver/riscv64" \
         "$SRC/kernel/src/mm" "$SRC/target/riscv64-qemu-virt" \
         "$SRC/docs" "$SRC/tools/aero-ld/src"

# 内核源码
cp kernel/src/main.aero "$SRC/kernel/src/"
cp kernel/src/userapp.aero "$SRC/kernel/src/"
cp kernel/src/boot/riscv64/start.S kernel/src/boot/riscv64/trap.S "$SRC/kernel/src/boot/riscv64/"
cp kernel/src/driver/riscv64/uart.c kernel/src/driver/riscv64/clint.c \
   kernel/src/driver/riscv64/libc_stub.c kernel/src/driver/riscv64/libgcc_stub.c "$SRC/kernel/src/driver/riscv64/"
cp kernel/src/mm/phys.c kernel/src/mm/heap.c "$SRC/kernel/src/mm/"
cp kernel/src/sched.c kernel/src/api.c kernel/src/syscall_shim.S "$SRC/kernel/src/"
cp kernel/Aero.toml "$SRC/kernel/"
cp target/riscv64-qemu-virt/linker.ld "$SRC/target/riscv64-qemu-virt/"

# 构建脚本
cp build.sh "$SRC/"
cp run-qemu.sh test-boot.sh test-interrupt.sh "$SRC/"
chmod +x "$SRC/"*.sh

# 文档
cp README.md docs/BUILD.md docs/RUN.md docs/CHANGELOG.md docs/P1-验收报告.md "$SRC/docs/"
cp -r public "$SRC/public"

# aero-ld 链接器（Rust 源码 + release 二进制）
cp -r tools/aero-ld/Cargo.toml tools/aero-ld/src "$SRC/tools/aero-ld/"
cp tools/aero-ld/target/release/aero-ld "$SRC/tools/aero-ld/"

# Aero 编译器（有外网时从 GitHub 下载；没有就提示）
AERO_REL="${RELNAME}-source/aero-compiler"
mkdir -p "$AERO_REL"
AERO_URL="https://github.com/SereinCin/aero-lang/releases/download/v1.2.4/aero-v1.2.4-linux-x86_64.tar.gz"
if curl -fsSL --connect-timeout 10 -o "$RELEASE_DIR/aero.tar.gz" "$AERO_URL" 2>/dev/null; then
    echo "    Aero 编译器: 已下载 v1.2.4 Linux release"
    tar -xzf "$RELEASE_DIR/aero.tar.gz" -C "$AERO_REL" --no-same-permissions --no-same-owner
    cp -r "$AERO_REL"/bin "$AERO_REL"/lib "$AERO_REL"/include "$AERO_REL" 2>/dev/null || true
    cp "$AERO_REL"/bin/aero "$AERO_REL/" 2>/dev/null || true
    rm "$RELEASE_DIR/aero.tar.gz"
else
    echo "    Aero 编译器: 外网不可达，跳过。用户自行从 $AERO_URL 下载"
fi

( cd "$RELEASE_DIR" && zip -r "${RELNAME}-source.zip" "${RELNAME}-source" -x "*.DS_Store" )
rm -rf "$SRC"
echo "    → ${RELNAME}-source.zip"

# ---------------------------------------------------------------------------
# 汇总
# ---------------------------------------------------------------------------
echo ""
echo "=== 发布完成 ==="
ls -lh "$RELEASE_DIR/"*.zip
echo ""
echo "公开包（2 个）："
echo "  ${RELNAME}-riscv64-qemu.zip   用户拿到就能在 QEMU 里跑"
echo "  ${RELNAME}-source.zip         完整源码 + aero-ld + Aero 编译器"
