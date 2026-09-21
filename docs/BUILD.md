# BUILD.md — 构建步骤

## 依赖

| 工具 | 最低版本 | 用途 |
|------|----------|------|
| clang | 18+ | C 编译 / 汇编 / 链接（集成 lld） |
| riscv64 binutils | 2.42+ | objcopy → 生成 `.bin` |
| cargo / rustc | 1.80+ | 编译 aero-ld 链接器 |
| Aero 编译器 | 1.2.4 | 编译 `.aero` 源文件 → riscv64-unknown-none |
| GNU make | 4.x | Makefile 构建（可选） |

## 环境要求

- Linux（推荐 Ubuntu 24.04 / WSL2 Ubuntu）
- 磁盘 ≥ 500 MB（含 Rust target / LLVM 库）

## 安装（Ubuntu）

```bash
# LLVM / clang / lld
wget -O - https://apt.llvm.org/llvm.sh | sudo bash -s 22
sudo apt-get install -y clang llvm lld

# RISC-V binutils（生成 .bin 用）
sudo apt-get install -y binutils-riscv64-linux-gnu

# QEMU（运行时需要，构建不需要）
sudo apt-get install -y qemu-system-riscv64

# Rust / cargo（如果还没装）
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# Aero 编译器（二选一）
# 选项 A：从 GitHub release 下载 Linux 版本
curl -fsSLO https://github.com/SereinCin/aero-lang/releases/download/v1.2.4/aero-v1.2.4-linux-x86_64.tar.gz
tar -xzf aero-v1.2.4-linux-x86_64.tar.gz
sudo cp bin/aero /usr/local/bin/
# 选项 B：本地编译（Windows 环境，aero.exe 在 Windows 盘）
# Aero 1.2.1---1.2.4/compiler/target/release/aero.exe
```

## 构建

```bash
cd AeroOS\ 26R1

# 主构建脚本（同时输出 ELF + BIN 规范文件名）
bash build.sh

# 或者用 Makefile
make -C target/riscv64-qemu-virt clean
make -C target/riscv64-qemu-virt
```

## 输出产物

```
build/
├── AeroOS.elf                        # 原始链接产物
├── AeroOS-26R1-riscv64.elf           # 规范名，QEMU -kernel 直接加载 (30 KB)
└── AeroOS-26R1-riscv64.bin           # 纯二进制镜像，供烧录 (8.6 KB)
```

## 交叉编译目标

AeroOS 26R1 当前仅支持 `riscv64 QEMU virt`：

```
-target riscv64-unknown-elf
-march=rv64gc
-mabi=lp64
-mcmodel=medany
```

x86_64 / ARM64 / 真硬件移植属于后续版本。
