# AeroOS 26R1

> Hard real-time OS kernel written from scratch in Aero.
> RISC-V QEMU virt · 26R 出生线 · Apache-2.0

---

## 这是什么

AeroOS 是一个**硬实时操作系统内核**，设计目标：**端到端中断-线程延迟 ≤ 1µs**（26R 系列 target）。用 [Aero](https://github.com/SereinCin/aero-lang) 语言从头编写——一种专为系统编程设计的语言。

**26R1 是 AeroOS 的第一个正式 Release**，目标平台是 **RISC-V QEMU virt**。它在 QEMU 上完整运行，包含 preemptive scheduler、timer interrupt、U-mode task + syscall、Aero 语言用户态程序。

## 你能做什么

| 你是 | 你可以 |
|------|--------|
| 想跑起来试试的开发者 | [QUICKSTART.md](QUICKSTART.md) — 10 分钟在 QEMU 里启动 |
| 想知道内核怎么工作 | [ARCHITECTURE.md](ARCHITECTURE.md) — 启动链、调度器、上下文切换 |
| 想在 AeroOS 上写用户态程序 | [WRITING-UMODE-APPS.md](WRITING-UMODE-APPS.md) — 用 Aero 语言写 U-mode 程序 |
| 想查 API / syscall | [API-REFERENCE.md](API-REFERENCE.md) + [SYSCALLS.md](SYSCALLS.md) |
| 想移植到真硬件 | [HARDWARE.md](HARDWARE.md) — 地址映射、定时器、外设 |
| 想知道版本怎么命名 | [VERSIONING.md](VERSIONING.md) |

## 核心特性（26R1）

- ✅ RISC-V 64-bit QEMU virt 完整启动
- ✅ OpenSBI 固件对接（FW_DYNAMIC）
- ✅ NS16550 UART console
- ✅ Physical page allocator + kmalloc / kfree
- ✅ Timer interrupt（CLINT via legacy SBI set_timer）
- ✅ Preemptive round-robin scheduler
- ✅ 30-register 240-byte context frame
- ✅ U-mode tasks + ecall syscall dispatch
- ✅ Aero 语言 U-mode 程序直接链接进内核镜像

## 设计原则（永远不违背）

1. **Determinism over average speed.** 最坏情况才是关键。
2. **Single address space.** 不切页表，不 TLB shootdown。
3. **Fast path = zero allocation.** 任何 malloc = 无限抖动。
4. **Interrupts reach threads directly.** 无通用框架，无 dispatch，无 accounting。
5. **No global interrupt-disable / preemption-disable critical sections.** 用优先级屏蔽。
6. **Measurement infrastructure is first-class.** 与内核同生共死，不是事后追加。

## 文档索引

```
public/
├── README.md                    ← 你正在读
├── QUICKSTART.md                ← 10 分钟跑起来
├── ARCHITECTURE.md              ← 内核架构总览
├── API-REFERENCE.md             ← C / Aero API 参考
├── SYSCALLS.md                  ← U-mode syscall 表
├── WRITING-UMODE-APPS.md        ← 怎么用 Aero 写用户态程序
├── HARDWARE.md                  ← QEMU virt 硬件映射 / 定时器 / 内存布局
├── VERSIONING.md                ← 版本命名规范（26 / 27 / LTS / STS / T 补丁）
└── CHANGELOG.md                 ← 版本更新记录
```
