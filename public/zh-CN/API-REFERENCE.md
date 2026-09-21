# API Reference — AeroOS 26R1

所有公开 API 按**调用者角色**分两组：

- **内核态 API**（S-mode，C / Aero `extern "C"` 调用）— 写内核时用
- **用户态 syscall**（U-mode，Aero / asm 调用 `ecall`）— 写用户程序时用

Syscall 详细表见 [SYSCALLS.md](SYSCALLS.md)。

---

## 内核态 API（S-mode）

### UART

```c
void aeroos_uart_puts(const char *msg);
```
打印以 null 结尾的字符串到 NS16550 UART0。阻塞直到发送完成。

```c
void aeroos_uart_putc(char c);
```
打印单个字符。

**Aero 声明**（`extern "C"`）：
```aero
extern "C" fn aeroos_uart_puts(msg: str);
```

### 定时器

```c
void timer_enable(void);
```
启动 timer interrupt。内部先调 `SBI set_timer` arm 一个新的 MTIP 触发点，再开 `STIE` + `SIE`。

```c
uint64_t clint_mtime_read(void);
```
读 CLINT mtime 计数器（10 MHz，QEMU virt）。返回当前时间戳。

```c
void aeroos_wait_timer_ticks(int64_t n);
```
阻塞等待 n 次 timer interrupt。用于自测。

### 调度器

```c
int scheduler_create(void (*entry)(void));
```
创建 S-mode task。entry 是函数指针，task 初始状态 = SP mode。

```c
int scheduler_create2(uint64_t entry, uint8_t priority);
```
创建 task。entry 是虚拟地址（U-mode 或 S-mode 都可以）。priority 当前未实现，保留参数。创建时自动初始化 context frame（sepc = entry，sstatus.SPP 决定返回模式）。

```c
uint64_t scheduler_tick(void);
```
Round-robin 选下一个 task，返回新 task 的 `saved_sp`（供 trap.S 切 sp 用）。

```c
void scheduler_demo(void);
```
demo 用：创建 4 个 S-mode worker + 1 个 U-mode Aero userapp。

### 内存

```c
void *aeroos_alloc_page(void);
void  aeroos_free_page(void *p);
```
物理页分配器，每次分配/释放 4 KB 页。从 `_kernel_end` 开始向高位走。

```c
void *kmalloc(size_t size);
void  kfree(void *p);
```
内核堆分配器，在物理页之上实现。fast path 不 malloc（设计原则 3），但调度器和 task 创建需要。

---

## 用户态 Syscall（U-mode）

用户态程序通过汇编 shim 发 `ecall`（scause=8），a7 寄存器指定 syscall 编号。

**Aero 声明**：
```aero
extern "C" fn sys_write(s: str, n: i64) -> i64;
extern "C" fn sys_yield();
extern "C" fn sys_exit();
extern "C" fn sys_fork(entry: u64) -> i64;
```

**签名详表**：

### `sys_write(s, n) -> i64`
| | |
|---|---|
| 功能 | 向 UART0 写入字节 |
| a7 | 1 |
| a0 | 字符串指针 `s` |
| a1 | 长度 `n`（实际写入 min(n, strlen(s))） |
| 返回 | 写入字节数（成功 = n） |
| 后端 | `aeroos_sys_write()` in `sched.c` |

```aero
// 示例
extern "C" fn sys_write(s: str, n: i64) -> i64;

fn hello() {
    sys_write("hello\n", 6);
}
```

### `sys_yield()`
| | |
|---|---|
| 功能 | 主动让出 CPU，触发 round-robin 调度切换 |
| a7 | 2 |
| 返回 | 无（正常返回） |
| 后端 | asm handler in `trap.S`（直接 j scheduler_tick） |

```aero
// 典型用法：loop + yield，配合 S-mode 任务公平运行
loop {
    do_work();
    sys_yield();
}
```

### `sys_exit()`
| | |
|---|---|
| 功能 | 终止当前 U-mode task |
| a7 | 3 |
| 返回 | 不返回 |
| 后端 | asm handler in `trap.S` |

### `sys_fork(entry) -> i64`
| | |
|---|---|
| 功能 | 从 U-mode 创建新的 U-mode task |
| a7 | 4 |
| a0 | 新 task 的入口地址 `entry` |
| 返回 | 新 task 的 task ID（≥ 0 成功，-1 失败） |
| 后端 | `aeroos_sys_fork()` in `sched.c` → `scheduler_create2()` |

```aero
// 注意：entry 必须是 U-mode 程序内可执行地址
// 编译后 link.ld 里 userapp 代码段地址由 aero-ld 决定
sys_fork(some_other_fn as u64);
```

---

## Aero `extern "C"` 规则

Aero 语言不支持 inline asm（26R1 版本），所有 syscall 必须通过 `extern "C"` + 汇编 shim 暴露：

```
userapp.aero  →  syscall_shim.S (汇编 ecall)  →  trap.S (trap_ecall handler)  →  C backend
```

`syscall_shim.S` 必须提供 C 兼容符号（`sys_write`, `sys_yield` 等），这样 Aero `extern "C"` 才能链接到它们。

---

## 完整符号列表

```
内核态 C:
  aeroos_uart_puts       aeroos_uart_putc
  aeroos_sys_write       aeroos_sys_fork
  scheduler_create       scheduler_create2
  scheduler_tick         scheduler_demo   scheduler_advance
  timer_enable           clint_mtime_read  aeroos_wait_timer_ticks
  aeroos_alloc_page      aeroos_free_page
  kmalloc                kfree
  worker_0               worker_1           worker_2           worker_3

用户态 syscall (a7 → 编号):
  sys_write   (a7=1)     sys_yield (a7=2)
  sys_exit    (a7=3)     sys_fork  (a7=4)
```
