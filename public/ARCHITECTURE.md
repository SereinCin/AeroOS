# Architecture — AeroOS 26R1 内核架构

## 启动链

```
┌─────────────────────────────────────────────────────────────┐
│  QEMU riscv64 virt                                           │
│                                                              │
│  OpenSBI v1.3 (FW_DYNAMIC)                                   │
│  0x80000000 ──────────────────┐                             │
│                               │ load                         │
│  AeroOS 26R1                  ▼                             │
│  0x80200000 ─────────────  _start (start.S)                 │
│                               │                              │
│                               ▼                              │
│                         kernel_start (main.aero)             │
│                               │                              │
│                 ┌─────────────┼──────────────┐              │
│                 ▼             ▼              ▼              │
│         uart_init()    scheduler_demo()  timer_enable()      │
│                                                    │         │
│                 ┌─────────────────────────────────┘         │
│                 ▼                                            │
│          worker_0() ← loop, 等 timer interrupt 抢占          │
└─────────────────────────────────────────────────────────────┘
```

## 内存布局（QEMU virt）

```
0x00000000 ─────────┐
                    │
0x10000000 ─────────┤  NS16550 UART0 THR
                    │
0x20000000 ─────────┤  QEMU virt MMIO
                    │
0x80000000 ─────────┤  OpenSBI FW_DYNAMIC (~322 KB)
                    │
0x80200000 ─────────┤  AeroOS 内核镜像（.text + .rodata + .data）
                    │  ~65 KB
0x80303000 ─────────┤  _kernel_end（heap start）
                    │  kmalloc / kfree / page allocator
                    │
                    │
0x88000000 ─────────┘  QEMU virt RAM top（128 MB）
```

## 上下文框架（240 字节）

```
struct context_frame {
    uint64_t ra;      // return address
    uint64_t t0;      // t0 - t6 (7 regs)
    uint64_t t1;
    ...
    uint64_t t6;
    uint64_t a0;      // a0 - a7 (8 regs)
    ...
    uint64_t a7;
    uint64_t s0;      // s0 - s11 (12 regs)
    ...
    uint64_t s11;
    uint64_t sepc;    // program counter
    uint64_t sstatus; // supervisor status register
};
// total = 30 regs × 8 B = 240 B
```

### trap entry / exit

```
trap_entry (trap.S):
    csrrw sp, sscratch, sp          # 交换 sp（保存当前 task 的 sp）
    addi  sp, sp, -240              # 分配 context frame
    sd    ra,   0(sp); sd t0, 8(sp) # push 所有 30 个寄存器
    ...
    sd    sepc, 224(sp); sd sstatus, 232(sp)
    mv    sp, sscratch              # sp 恢复成栈指针
    # 然后跳 handler（timer / ecall / exception）

trap_return (trap.S):
    ld    ra,   0(sp); ld t0, 8(sp) # pop 所有 30 个寄存器
    ...
    ori   sstatus, sstatus, 0x20    # 强制 SPIE=1（关键！）
    csrw  sstatus, sstatus
    ld    sepc, 224(sp)
    sret                            # 返回原模式（S-mode 或 U-mode）
```

> **为什么强制 SPIE=1？** Hardware trap entry 会自动把 SPIE 清零。如果不强制，sret 后 SIE = SPIE = 0，中断永远不会再响应。这是 26R1 最隐蔽的 bug 之一。

## 抢占式调度

```
Timer interrupt (每 0.2s, scause=5)
    │
    ▼
trap_timer (trap.S):
    1. SBI set_timer → 重新 arm timer（没有这步，MTIP 永远不会再触发）
    2. current_task->saved_sp = sp（保存当前 task 的 frame 底部）
    3. scheduler_tick() → round-robin 选下一个 task
    4. sp = next_task->saved_sp（切到下一个 task 的栈）
    5. j trap_return → sret 进入新 task
```

**Round-robin 顺序**：T0 → T1 → T2 → T3 → U-mode userapp → T0 → ...

## Syscall 流程（U-mode → S-mode）

```
userapp.aero                     syscall_shim.S                    trap.S                    api.c / trap.S
───────────                      ────────────────                  ────────                  ──────────────
sys_write("hello", 16);
    │
    ▼ (extern "C" → 汇编 shim)
sys_write:
    li a7, 1                     ← syscall 编号
    ecall                        ← scause=8 → trap_ecall
    └ return
                                  │
                                  ▼ trap_ecall:
                                  a7 == 1 → aeroos_sys_write
                                  a7 == 2 → trap_yield (asm)
                                  a7 == 3 → trap_exit  (asm)
                                  a7 == 4 → aeroos_sys_fork
                                  │
                                  ▼
                                  执行 + trap_return + sret
                                  │
                                  ▼ 返回 userapp
```

| a7 | Syscall | 后端 |
|----|---------|------|
| 1 | `sys_write` | `aeroos_sys_write()` in `sched.c` |
| 2 | `sys_yield` | asm handler in `trap.S`（直接调度切换） |
| 3 | `sys_exit` | asm handler in `trap.S` |
| 4 | `sys_fork` | `aeroos_sys_fork()` in `sched.c` |

## U-mode task 创建

```
// S-mode：把入口地址传给 scheduler_create2()
scheduler_create2(userapp_main, 1);   // entry + priority

// scheduler_create2 初始化 context frame：
//   - sepc = userapp_main
//   - sstatus.SPP = 0  (之前模式 = U-mode)
//   - sstatus.SPIE = 1 (sret 后重新开中断)
//   - 30 个寄存器清零
//   - saved_sp = frame 底部指针

// Timer interrupt 触发时 → trap_return → sret
//   SPP=0 → sret 进入 U-mode
//   SPIE=1 → 重新开 SIE
```

## 语言

| 组件 | 语言 |
|------|------|
| boot entry / trap handler | 汇编（RISC-V asm in `trap.S`, `start.S`） |
| drivers / scheduler / syscall backend | C |
| kernel entry / userland apps | [Aero 1.2](https://github.com/SereinCin/aero-lang) |
| linker | aero-ld（自研，Rust + nom） |

## 关键数据结构

**Task** (`sched.c`)
```c
typedef struct task {
    uint64_t saved_sp;       // context frame bottom (entry)
    uint64_t entry;          // entry point (S-mode 或 U-mode 地址)
    uint8_t  is_umode;       // 1 = U-mode, 0 = S-mode
} task_t;
```

**Page allocator** (`phys.c`)
```c
// 从 _kernel_end 开始，每次分配 4KB 页
void *aeroos_alloc_page(void);
void  aeroos_free_page(void *p);
```

**Heap** (`heap.c`)
```c
// 在物理页上实现 kmalloc/kfree
void *kmalloc(size_t size);
void  kfree(void *p);
```
