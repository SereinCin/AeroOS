// Minimal libgcc shim for AeroOS 26R1 — riscv64 softfloat / integer helpers.
// We don't enable hardware FPU in the toolchain flags to keep ABI uniform,
// so LLVM may emit calls to these helpers for wide integer ops. The float
// ones (__adddf3 etc.) should vanish with --gc-sections since our kernel
// never uses f64, but we provide them just in case.

#include <stdint.h>

// 64-bit signed / unsigned division and modulo
int64_t __divdi3(int64_t a, int64_t b)    { return a / b; }
int64_t __moddi3(int64_t a, int64_t b)    { return a % b; }
uint64_t __udivdi3(uint64_t a, uint64_t b){ return a / b; }
uint64_t __umoddi3(uint64_t a, uint64_t b){ return a % b; }

// float helpers — stub only, will be GC'd if unreferenced
double __adddf3(double a, double b)       { return a + b; }
double __subdf3(double a, double b)       { return a - b; }
double __muldf3(double a, double b)       { return a * b; }
double __divdf3(double a, double b)       { return a / b; }
double __negdf2(double a)                 { return -a; }
