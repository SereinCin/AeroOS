# Writing U-mode Apps — 用 Aero 语言写用户态程序

## 它怎么工作

```
userapp.aero (Aero 代码)
    │
    ▼ aero 编译器 --emit-obj --target riscv64-unknown-none
userapp.o (RISC-V 目标文件)
    │
    ▼ aero-ld + linker.ld → AeroOS-26R1-riscv64.elf
内核镜像（包含 S-mode 内核 + U-mode userapp）
    │
    ▼ QEMU -kernel → OpenSBI → kernel_start → scheduler_demo()
scheduler_create2(userapp_main, 1)   ← 创建 U-mode task
    │
    ▼ timer interrupt / sret 进入
userapp_main() 在 U-mode 里运行！
```

**关键概念**：26R1 没有文件系统，U-mode 程序不是独立 ELF。它编译成 `.o` 之后和 S-mode 内核一起链接进同一个镜像。这是 single-address-space 设计原则的体现。

## 最小可运行示例

`myapp.aero`：
```aero
// 1. 声明 syscall（Aero 不支持 inline asm，必须从 C 导入）
extern "C" fn sys_write(s: str, n: i64) -> i64;
extern "C" fn sys_yield();

// 2. #[no_mangle] 保证符号名不被 Aero 混淆，scheduler_create2 能找到
#[no_mangle]
fn myapp_main() {
    let mut count = 0;
    loop {
        sys_write("hello from myapp\n", 17);
        count = count + 1;
        sys_yield();   // 主动让 CPU
    }
}
```

**但光写 `myapp.aero` 还不够**。你还需要告诉调度器"创建这个 task"。有两种方式：

### 方式 1：在 `main.aero` 里加一行（推荐，26R1 现状）

```aero
// main.aero 里 extern "C" 声明 scheduler_create2
extern "C" fn scheduler_create2(entry: u64, priority: u64);

#[entry]
#[no_mangle]
fn kernel_start() {
    aeroos_uart_puts("AeroOS 26R1 booting...\n");
    // ... 其他 demo ...

    scheduler_demo();       // 创建 T0-T3 S-mode + 默认 userapp
    // 如果你想加自己的 task：
    scheduler_create2(myapp_main as u64, 1);  // ← 加这一行

    timer_enable();
    worker_0();
}
```

### 方式 2：用 sys_fork 从已有 U-mode 创建新的（还没写过，理论可行）

```aero
#[no_mangle]
fn myapp_main() {
    sys_write("hello\n", 6);
    // sys_fork(another_app as u64);  // 创建另一个 U-mode task
}
```

## Syscall 汇编 shim

Aero 语言目前（v1.2.4）不支持 inline asm。每次 `ecall` 必须通过一个汇编包装函数。26R1 里已经写好了：

**`syscall_shim.S`**（你不用改，了解一下就行）：
```asm
    .section .text.userapp

# i64 sys_write(const char *s, i64 n)
    .globl  sys_write
    .type   sys_write, @function
sys_write:
    li   a7, 1
    ecall
    ret
    .size   sys_write, . - sys_write
```

build.sh 里这个文件会被编译成 `syscall_shim.o`，和你的 `.aero` 一起链接。

## 编译命令

```bash
# 用 Aero 编译器生成目标文件
aero build myapp.aero --emit-obj --target riscv64-unknown-none
# 产物：myapp.o

# 然后和其他 .o 一起链接
aero-ld -T linker.ld -o AeroOS.elf boot.o trap.o ... myapp.o syscall_shim.o ...
```

## 限制（26R1 已知）

| 限制 | 原因 | 什么时候解决 |
|------|------|-------------|
| 不能用 inline asm | Aero v1.2.4 还没实现 | 26R2+ 或者自己写 C shim |
| 没有 stdlib | AeroOS 是裸机内核，没有 libc | 用户程序自己写或引轻量库 |
| 不能 malloc | 没有堆分配器暴露给 U-mode | P2+ 加 U-mode heap |
| 没有文件系统 | 没 initrd，没 virtio-blk | 26R3 或 27 |
| 没有 PMP 保护 | OpenSBI 默认允许全地址访问 | 安全需求驱动 |
| link.ld 地址硬编码 | U-mode entry 必须在特定虚拟地址 | 加符号表/动态加载 |

## 调试 U-mode 程序

最简单的方法——**在 sys_write 里打点**：
```aero
#[no_mangle]
fn myapp_main() {
    sys_write("A: ", 3);   // 检查是否进了 myapp
    sys_write("B: ", 3);   // 检查某条路径
    // ...
    sys_write("C: done\n", 8);
}
```

如果想停住等你读，可以把 loop 改成只跑一次：
```aero
#[no_mangle]
fn myapp_main() {
    sys_write("hello once\n", 11);
    loop {
        sys_yield();   // 原地等
    }
}
```

## 完整目录结构参考

```
AeroOS-26R1/
├── kernel/src/
│   ├── main.aero              ← kernel entry (改这里调 scheduler_create2)
│   ├── userapp.aero           ← 官方示例 U-mode 程序
│   ├── boot/riscv64/
│   │   ├── start.S
│   │   └── trap.S             ← trap handler + syscall dispatch
│   ├── sched.c                ← scheduler_create2() / aeroos_sys_fork()
│   └── syscall_shim.S         ← ecall 汇编包装（U-mode → S-mode 的桥）
├── target/riscv64-qemu-virt/
│   └── linker.ld              ← 决定各段虚拟地址
├── build.sh                   ← 一键构建
└── run-qemu.sh                ← 一键运行
```
