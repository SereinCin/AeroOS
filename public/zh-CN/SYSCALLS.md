# Syscall Table — AeroOS 26R1

## 概述

U-mode 用户态程序通过 **ecall 指令**陷入 S-mode。trap.S 的 `trap_ecall` handler 根据 `a7` 寄存器分发到对应后端。

```
U-mode:  li a7, <syscall_num>
         ecall                  ← scause = 8, sret 返回
                              ↓
trap.S:  trap_ecall (scause & 0x3FF == 8)
              ↓
         a7 == 1 → aeroos_sys_write()
         a7 == 2 → asm yield handler
         a7 == 3 → asm exit handler
         a7 == 4 → aeroos_sys_fork()
              ↓
         trap_return → sret → 回到 U-mode
```

## 完整 syscall 表

| a7 | 名称 | a0 | a1 | a2 | 后端 | 26R1 状态 |
|----|------|----|----|----|------|----------|
| 1 | `sys_write` | `s: str*` | `n: i64` | — | C `aeroos_sys_write()` | ✅ 可用 |
| 2 | `sys_yield` | — | — | — | asm yield（直接调 scheduler_tick） | ✅ 可用 |
| 3 | `sys_exit` | — | — | — | asm exit（当前 task 停止） | ✅ 可用 |
| 4 | `sys_fork` | `entry: u64` | — | — | C `aeroos_sys_fork()` → `scheduler_create2()` | ✅ 可用 |

## sys_write (a7=1)

**C 签名**：
```c
int64_t sys_write(const char *s, int64_t n);
```

**参数**：
| 寄存器 | 含义 |
|--------|------|
| a0 | 字符串指针（虚拟地址，U-mode 可访问） |
| a1 | 要写入的字节数 |

**返回值**（a0）：实际写入字节数。成功 = min(n, strlen(s))，失败 = -1。

**示例**（汇编）：
```asm
    li   a7, 1
    la   a0, msg           # "hello from Aero\n"
    li   a1, 16
    ecall
```

**示例**（Aero）：
```aero
extern "C" fn sys_write(s: str, n: i64) -> i64;

sys_write("hello\n", 6);
```

后端实现（`sched.c`）：
```c
int64_t aeroos_sys_write(const char *s, int64_t n) {
    int64_t written = 0;
    for (int64_t i = 0; i < n; i++) {
        if (s[i] == '\0') break;
        aeroos_uart_putc(s[i]);
        written++;
    }
    return written;
}
```

## sys_yield (a7=2)

**参数**：无

**返回**：正常返回（task 被重新调度，可能换了别的 task）

**为什么重要**：26R1 是 cooperative yield + preemptive timer 双轨制：
- U-mode 程序**主动 yield** → 公平性好
- Timer interrupt **强制抢占**（0.2s 周期）→ 保证不饿死
- S-mode 内核代码**不能**用 sys_yield，它没有 ecall 权限

**后端**（`trap.S` 内联 asm handler）：
```asm
trap_yield:
    call    scheduler_tick
    mv      sp, a0
    j       trap_return
```

## sys_exit (a7=3)

终止当前 U-mode task。task context 框架保留在内存，当前版本不清理（这是已知限制，后续版本加回收）。

## sys_fork (a7=4)

从 U-mode 创建新的 U-mode task。

**参数**：
| 寄存器 | 含义 |
|--------|------|
| a0 | 新 task 的入口地址（虚拟地址） |

**返回**（a0）：新 task 的 task ID（≥ 0 成功），-1 失败。

**注意事项**：
1. `entry` 地址必须在 U-mode 代码段内。link.ld 把 userapp.aero 的代码放在 kernel image 特定段，entry 必须指向那里。
2. 新 task 的 sstatus 初始化成 U-mode（SPP=0, SPIE=1）。
3. 新 task 初始栈 = 独立 context frame（8 KB，从堆分配）。

## 新增 syscall 的流程

1. 在 `api.c` 添加 C backend：`int64_t aeroos_sys_xxx(uint64_t arg...)`
2. 在 `trap.S trap_ecall` handler 添加 a7 分发 case：
   ```asm
   li    t2, <new_a7>
   beq   t2, a7, trap_xxx
   ```
3. 在 `syscall_shim.S` 添加汇编 shim：
   ```asm
   .globl  sys_xxx
   .type   sys_xxx, @function
   sys_xxx:
       li   a7, <new_a7>
       ecall
       ret
   .size   sys_xxx, . - sys_xxx
   ```
4. 在 `public/SYSCALLS.md` 和 `public/API-REFERENCE.md` 更新表

## 已知限制

- Syscall 表目前只有 4 个（write / yield / exit / fork）。完整 POSIX 兼容（open / read / close / mmap 等）需要文件系统和页表，26R1 范围外。
- U-mode → kernel buffer 拷贝还没有，sys_write 直接读 U-mode 指针（OpenSBI 默认 PMP 允许全地址访问）。26R2+ 加 PMP 后需要加 copy_from_user。
- sys_fork 不复制地址空间（没有页表），创建的是新 task 指向同一份代码/数据。
