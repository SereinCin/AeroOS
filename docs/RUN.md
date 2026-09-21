# RUN.md — 如何启动 AeroOS 26R1

## 前置条件

- QEMU riscv64：`sudo apt install qemu-system-riscv64`
- 已构建：`bash build.sh`

## 一键启动

```bash
# 用默认构建产物
./run-qemu.sh

# 或者指定 ELF
./run-qemu.sh build/AeroOS-26R1-riscv64.elf
```

Ctrl-A X 退出 QEMU。

## 手动启动

```bash
qemu-system-riscv64 \
    -machine virt \
    -bios default \
    -kernel build/AeroOS-26R1-riscv64.elf \
    -nographic \
    -monitor none
```

`-bios default` 加载 OpenSBI 固件（QEMU 内置），OpenSBI 把 kernel ELF 放到 0x80200000 然后跳转。

## 预期输出

启动后依次看到：

```
OpenSBI v1.3           ← 固件 banner（前 30 行）
AeroOS 26R1 booting... ← kernel boot banner
sched: 4 S-mode + 1 U-mode tasks created   ← scheduler init
T0: idle loop          ← 4 个 S-mode worker 任务
T1: idle loop
T2: idle loop
T3: idle loop
hello from Aero        ← U-mode Aero userapp，持续打印
hello from Aero
...
```

### 任务映射

| 标识 | 类型 | 功能 |
|------|------|------|
| T0-T3 | S-mode (内核态) | worker 任务，每 0.2s timer interrupt 切换 |
| `hello from Aero` | U-mode (用户态) | Aero 语言编写的 userapp，通过 ecall 触发 sys_write |

### 硬件地址映射

```
0x80000000 - 0x8004FFFF   OpenSBI 固件 (322 KB)
0x80200000 - 0x80302FFF   AeroOS 内核 (.text + .data + .bss, ~65 KB)
0x80303000                heap start (kmalloc)
0x88000000                RAM top (128 MiB, QEMU virt 默认)
```

## 运行验证

```bash
# 验证能否 boot（3 秒 timeout）
./test-boot.sh

# 验证中断响应（10 秒 timeout）
./test-interrupt.sh
```

两个脚本 exit code 为 0 表示全部 PASS。详见 [P1-验收报告.md](P1-验收报告.md)。
