# CHANGELOG — AeroOS 26R1

**版本**：AeroOS 26R1 (初始 Release)
**发布日期**：2026-10-04
**目标平台**：riscv64 QEMU virt

---

## 核心里程碑

### Boot & Toolchain
- 68ab37e / 5f537af — 项目初始化 + QEMU virt bootable MVP
- 78004d8 — NS16550 UART driver + boot banner "AeroOS 26R1 booting..."
- ba8964c — 自研 aero-ld（Rust + nom），self-hosted RISC-V linker
- 82f8ede — WSL build.sh，clang integrated-as + Windows 侧 aero.exe

### 内存管理
- ac98ad7 — physical page-frame allocator，从 `_kernel_end` 开始
- b1c73c6 — kmalloc / kfree on phys pages

### 中断 & 调度
- 964047a — trap handler + CLINT 驱动骨架（初始禁用）
- 5f6e149 — 启用 S-mode timer interrupt（CLINT via legacy SBI set_timer）
- 4519b5c — preemptive round-robin scheduler，timer tick 驱动
- 8efeca0 — 修 timer 自测确定性行为
- **根因 bug 修复**：`trap.S trap_return` 强制 `SPIE=1`（hardware trap entry 清零 SPIE，sret 后 SIE=SPIE=0 → 中断永久关闭）
- **根因 bug 修复**：`timer_enable()` 必须先 `timer_arm()`（SBI set_timer 触发新 MTIP）

### U-mode & Syscall
- 9e4ea7a — U-mode task 框架 + ecall dispatch（scause=8），30-register 240B context frame，sys_write / sys_yield / sys_fork / sys_exit
- ab98b33 — **Aero 语言绑定**：`userapp.aero` 通过 `extern fn` + `syscall_shim.S` ecall 封装，编译进内核镜像，直接在 QEMU 里输出 "hello from Aero"

### CI
- 3ce6eed — GitHub Actions riscv64 QEMU virt boot verification workflow
- 429c23e / 05d9012 — CI tar utime / 权限问题修复

---

## 性能基线（P1.7 验收实测）

QEMU riscv64 virt，10 秒运行窗口：

| 指标 | 值 |
|------|-----|
| S-mode tasks | T0=331 T1=331 T2=331 T3=328 |
| 总 scheduler ticks | 1321 |
| U-mode syscalls (ecall) | 58565 |
| TRAP / panic | 0 |
| ELF 镜像大小 | 30,928 B |
| BIN 镜像大小 | 8,612 B |

---

## 已知限制（26R1 范围内，不阻塞发布）

- U-mode 无 PMP 内存保护（OpenSBI 默认允许全地址访问）
- Syscall 集仅 write / yield / exit / fork（4 个）
- Timer interrupt 周期固定 0.2s（10 MHz timebase + SBI set_timer）
- Hard real-time 延迟实测数据（≤1µs target）尚未采集
- EVT 真机点亮（VisionFive 2 / HiFive 1）属独立工程样机测试，非 T 补丁范畴
