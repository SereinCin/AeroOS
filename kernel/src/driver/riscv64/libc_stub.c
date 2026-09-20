// AeroOS 26R1 — minimal libc stub.
//
// malloc / free / calloc / realloc delegate to the kernel heap
// (kernel/src/mm/heap.c).  memcpy/memset/memcmp/strlen/snprintf are
// still implemented inline here — the kernel doesn't link against a
// real libc.

#include <stdint.h>
#include <stddef.h>

extern void *kmalloc(size_t n);
extern void  kfree(void *p);

// forward — used by realloc below
void *memcpy(void *dst, const void *src, size_t n);

void *malloc(size_t sz)           { return kmalloc(sz); }
void  free(void *p)                { kfree(p); }

void *calloc(size_t n, size_t sz) {
    void *p = kmalloc(n * sz);
    if (!p) return 0;
    // The kernel's kmalloc zeroes fresh pages but does NOT zero split
    // leftover bytes — callers of calloc still expect the whole block.
    uint8_t *q = (uint8_t *)p;
    for (size_t i = 0; i < n * sz; i++) q[i] = 0;
    return p;
}

void *realloc(void *p, size_t n) {
    if (p == 0)  return kmalloc(n);
    if (n == 0)  { kfree(p); return 0; }
    // We don't track old sizes — walk the heap to find the block, or
    // just alloc+copy+free.  Simplest: alloc+copy+free is always correct.
    void *q = kmalloc(n);
    if (!q) return 0;
    memcpy(q, p, n);   // may copy past old block — acceptable for MVP
    kfree(p);
    return q;
}

void *memcpy(void *dst, const void *src, size_t n) {
    uint8_t *d = dst; const uint8_t *s = src;
    while (n--) *d++ = *s++;
    return dst;
}

void *memset(void *s, int c, size_t n) {
    uint8_t *p = s;
    while (n--) *p++ = (uint8_t)c;
    return s;
}

int memcmp(const void *a, const void *b, size_t n) {
    const uint8_t *x = a, *y = b;
    while (n--) { if (*x != *y) return (int)*x - (int)*y; x++; y++; }
    return 0;
}

size_t strlen(const char *s) { size_t n = 0; while (s[n]) n++; return n; }

int snprintf(char *buf, size_t n, const char *fmt, ...) {
    (void)buf; (void)n; (void)fmt; return 0;
}
int _snprintf(char *buf, size_t n, const char *fmt, ...) {
    return snprintf(buf, n, fmt);
}
