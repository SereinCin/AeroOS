// Minimal libc stub for AeroOS 26R1
// Only what stdlib and runtime truly need.

#include <stdint.h>
#include <stddef.h>

void* malloc(size_t sz) { (void)sz; return 0; }
void free(void* p)      { (void)p; }

void* memcpy(void* dst, const void* src, size_t n) {
    uint8_t* d = dst; const uint8_t* s = src;
    while (n--) *d++ = *s++;
    return dst;
}

void* memset(void* s, int c, size_t n) {
    uint8_t* p = s;
    while (n--) *p++ = (uint8_t)c;
    return s;
}

int memcmp(const void* a, const void* b, size_t n) {
    const uint8_t* x = a, *y = b;
    while (n--) { if (*x != *y) return (int)*x - (int)*y; x++; y++; }
    return 0;
}

size_t strlen(const char* s) { size_t n = 0; while (s[n]) n++; return n; }

int snprintf(char* buf, size_t n, const char* fmt, ...) {
    (void)buf; (void)n; (void)fmt; return 0;
}
int _snprintf(char* buf, size_t n, const char* fmt, ...) {
    return snprintf(buf, n, fmt);
}
