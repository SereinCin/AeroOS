# Hardware — QEMU virt 硬件映射

26R1 目标平台是 **QEMU riscv64 virt**（`-machine virt`）。本节描述这个平台的内存、外设、定时器——写驱动或移植到真机时需要参考。

## 平台信息

| 项 | 值 |
|----|-----|
| QEMU machine | `riscv64 virt` |
| CPU | 单 hart, RV64GC |
| RAM | 128 MB（默认） |
| BIOS | OpenSBI v1.3 (default, FW_DYNAMIC) |
| Timer | ACLINT MTIMER @ 10 MHz |
| Console | UART8250 (NS16550) @ 1.8432 MHz |

## 物理内存布局

```
0x00000000 ──────────────────────────────────────────┐
                                                      │
0x10000000 ─────────┐                                │
                     │ MMIO range                     │ 设备寄存器
0x100000C0 ─────────┤ UART8250 UART0                 │
                     │ (NS16550, 3.3V)                │
0x10000000 ─────────┘                                │
                                                      │
0x20000000 ─────────┐                                │
                     │ QEMU virt reserved MMIO        │
0x20FFFFF0 ─────────┘                                │
                                                      │
0x80000000 ─────────┐                                │
                     │ OpenSBI FW_DYNAMIC             │
0x8004FFFF ─────────┘                                │ 固件
                     │ (~322 KB)                       │
0x80080000 ─────────┐                                │
                     │ ACLINT MTIMER                  │
0x800BFFFF ─────────┤ (10 MHz, read-only)             │
0x800C0000 ─────────┤ ACLINT MSWI                     │
0x800FFFFF ─────────┘                                │
                                                      │
0x80200000 ─────────┐                                │
                     │ AeroOS 内核镜像                │
0x802FFFFF ─────────┤  (.text + .rodata + .data)      │ 内核
                     │  ~65 KB                          │
0x80300000 ─────────┤ _kernel_end                     │
                     │ kmalloc / page allocator        │
                     │                                  │ 堆
                     │                                  │
                     │                                  │
0x88000000 ─────────┘                                │ RAM top
```

## UART8250 (NS16550) — 串口

**基地址**：`0x10000000`

| 偏移 | 读 | 写 |
|------|----|----|
| +0 | RBR (接收缓冲) | THR (发送保持) |
| +1 | IER | IER |
| +2 | IIR | FCR |
| +3 | LCR | LCR |
| +4 | MCR | MCR |
| +5 | LSR | — |
| +6 | MSR | — |
| +7 | SCR | SCR |

**波特率**：默认 115200，8N1（QEMU 硬编码）

**26R1 驱动**（`uart.c`）：
```c
#define UART0_THR  0x10000000

void aeroos_uart_putc(char c) {
    while ((*(volatile uint8_t*)UART0_LSR & 0x20) == 0) {
        // wait THR empty
    }
    *(volatile uint8_t*)UART0_THR = c;
}
```

## CLINT MTIMER — 定时器

**基地址**：`0x80080000`（QEMU virt 上）

**频率**：10 MHz（timebase = 0.1 µs per tick）

**26R1 用法**：通过 **legacy SBI set_timer** 设置新触发时间（不直接写 CLINT 寄存器）：
```
rdtime a0              # 读当前 time
add    a0, a0, 2000000 # 加 0.2s × 10MHz = 2,000,000 ticks
li     a1, a0
li     a7, 0           # legacy SBI EID=0 (Set Timer)
ecall                  # OpenSBI 设置 MTIMECMP = a1
```

**Timer interrupt handler 必须做两件事**：
1. **re-arm**：调 SBI set_timer 设新的 MTIMECMP（没有这步，MTIP 永远不重新 pending）
2. **STIE + SIE 必须打开**：否则即使 MTIP pending 也不会触发 trap

```c
// timer_enable() 必须做：
timer_arm(TIMER_INTERVAL);   // ① 设 MTIMECMP
csrs sie, (1 << 5);          // ② 开 STIE (bit 5)
csrs sstatus, (1 << 1);      // ③ 开 SIE  (bit 1)
```

> **根因 bug 回顾**：如果只做 ②③ 不做 ①，MTIMECMP 已经被硬件超过了，永远不会再 pending MTIP。这是 26R1 早期 timer interrupt 不触发的原因。

## OpenSBI FW_DYNAMIC — 固件

OpenSBI v1.3 启动流程：
```
M-mode: OpenSBI 初始化 PMP + timer + console
        │
        ▼ FW_DYNAMIC: 把 kernel ELF 加载到 RAM
        │
        ▼ OpenSBI jump to kernel @ 0x80200000
        │ (sret to S-mode, SPP=1, SPV=1, S-mode supervisor)
        ▼
        AeroOS kernel_start() @ S-mode
```

**FW_DYNAMIC 语义**：OpenSBI 不硬编码 kernel 地址，它读 `-kernel` 参数里的 ELF header，按 ELF load segment 把 kernel 放到 RAM。我们的 linker.ld 里：
```ld
ENTRY(_start)
SECTIONS {
    . = 0x80200000;
    .text : { ... }
    .data : { ... }
}
```

## QEMU 启动命令详解

```bash
qemu-system-riscv64 \
    -machine virt                    # QEMU virt machine (有 OpenSBI / CLINT / UART)
    -bios default                    # 用 QEMU 内置 OpenSBI v1.3
    -kernel AeroOS-26R1-riscv64.elf  # OpenSBI FW_DYNAMIC 加载 + 跳转
    -nographic                      # 不弹图形窗口，输出到 stdout
    -monitor none                    # 不弹 monitor（Ctrl-A C 的那种）
    -smp 1                           # 单 hart（26R1 还没做 SMP）
    -m 128M                          # 128MB RAM（默认值，显式写上更清楚）
```

| 参数 | 为什么 |
|------|--------|
| `-machine virt` | 提供 OpenSBI FW_DYNAMIC 固件 + CLINT MTIMER + UART8250 + PLIC |
| `-bios default` | 用 QEMU 打包的 OpenSBI v1.3，不需要自己找 firmware |
| `-kernel` | OpenSBI FW_DYNAMIC 语义：读 ELF header → 按 load segment 放 RAM → 跳 ELF entry |
| `-nographic` | kernel UART 输出直接到终端，方便 debug |

## 移植到真机时需要改的地方

| 组件 | QEMU virt 值 | 真机需要什么 |
|------|-------------|-------------|
| UART base | `0x10000000` | VisionFive 2: `0x10000000` 相同；HiFive: 不同，查手册 |
| Timer 频率 | 10 MHz | VisionFive 2: 10 MHz 相同；其他板不一定 |
| CLINT base | `0x80080000` | 有的板在 `0x20000000` |
| OpenSBI | QEMU 打包 | 自己编译 FW_DYNAMIC firmware |
| Boot media | `-kernel` 直接加载 | SD 卡 / SPI NOR / USB，OpenSBI 先从介质加载再跳 kernel |
| Memory size | 128 MB | 真机可能 2 GB+ |

## 地址映射总结

```
AeroOS 26R1 kernel 链接地址：
  .text   = 0x80200000 (entry point)
  .rodata = 紧随 .text
  .data   = 紧随 .rodata
  .bss    = 紧随 .data（清零）
  heap    = _kernel_end（动态，页分配器从这里开始）

UART0   = 0x10000000
CLINT   = 0x80080000
```
