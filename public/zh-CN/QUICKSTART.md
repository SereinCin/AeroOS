# Quickstart — 10 分钟跑起来

## 你需要什么

| 工具 | 用途 | 安装（Ubuntu/WSL） |
|------|------|-------------------|
| clang 18+ / lld | C 编译 + 链接 | `wget -O - https://apt.llvm.org/llvm.sh \| sudo bash -s 22` |
| riscv64 binutils | 生成 `.bin` | `sudo apt install binutils-riscv64-linux-gnu` |
| QEMU riscv64 | 运行 | `sudo apt install qemu-system-riscv64` |
| Rust / cargo | 编译 aero-ld | `curl ... rustup.rs` |
| Aero 编译器 1.2.4 | 编译 `.aero` | `curl -L github.com/SereinCin/aero-lang/releases/download/v1.2.4/aero-v1.2.4-linux-x86_64.tar.gz \| tar xz` |

## 一步构建

```bash
# 1. 解压源码（你已经有了）
cd AeroOS-26R1

# 2. 一键构建（需要 WSL 里 clang + cargo + riscv binutils）
bash build.sh
```

输出：
```
build/AeroOS-26R1-riscv64.elf   30 KB   ← QEMU -kernel 直接加载
build/AeroOS-26R1-riscv64.bin    8 KB   ← 纯二进制，供烧录
```

## 一键运行

```bash
# 启动 QEMU，看到 "AeroOS 26R1 booting..." 和 "hello from Aero" 就成功了
./run-qemu.sh
# Ctrl-A X 退出 QEMU
```

## 一键验收

```bash
# 测试 1：能不能 boot（3s timeout）
./test-boot.sh
# → [PASS] boot banner printed
# → [PASS] no TRAP / panic / exception

# 测试 2：中断是否正常响应（10s timeout）
./test-interrupt.sh
# → [PASS] timer interrupt OK — 1300+ scheduler ticks
# → [PASS] U-mode ecall OK — 50000+ syscalls
# → [PASS] zero TRAP / panic / exception
```

两个脚本 exit code = 0 表示全部 PASS。

## 预期输出

```
OpenSBI v1.3
...（固件 banner，约 30 行）...
AeroOS 26R1 booting...
sched: 4 S-mode + 1 U-mode tasks created
T0: idle loop
T1: idle loop
T2: idle loop
T3: idle loop
hello from Aero
hello from Aero
...（持续，每 0.2s 切换任务）...
```

## 任务映射

| 看到的 | 类型 | 代码 |
|--------|------|------|
| `T0` - `T3` | S-mode（内核态） | `worker_0()` - `worker_3()` in `sched.c` |
| `hello from Aero` | U-mode（用户态） | `userapp_main()` in `kernel/src/userapp.aero` |

## 常见问题

**Q: 我只有 Windows，没有 Linux？**
用 WSL2 Ubuntu。本项目就是在 WSL2 里开发的。

**Q: 我没有 WSL 怎么办？**
用 QEMU 跑一个 Ubuntu 虚拟机，然后在里面构建。

**Q: 我想用 Makefile 而不是 build.sh？**
有：`make -C target/riscv64-qemu-virt`

**Q: 构建报 "riscv64-linux-gnu-objcopy not found"？**
`sudo apt install binutils-riscv64-linux-gnu`

**Q: QEMU 报错 "Could not load bios"？**
`-bios default` 参数用的是 QEMU 内置 OpenSBI。如果你的 QEMU 版本不支持 default，改成 `-bios /path/to/opensbi/generic/firmware/firmware.elf`
