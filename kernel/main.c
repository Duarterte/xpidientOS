/* main.c - the first C code your OS ever runs.
 * No libc. No stdint.h. Only kernel/types.h and the VGA framebuffer. */
#include "types.h"

/* ---- VGA text mode -------------------------------------------------- */
#define VGA_BASE   0xB8000UL
#define VGA_COLS   80
#define VGA_ROWS   25

#define ATTR_BLACK   0x0
#define ATTR_GREEN   0x2
#define ATTR_CYAN    0x3
#define ATTR_RED     0x4
#define ATTR_GREY    0x7
#define ATTR_WHITE   0xF

/* One cell = 2 bytes: low byte ASCII, high byte attribute.
 * volatile: the VIDEO HARDWARE reads this memory; the compiler must not
 * assume these writes are dead stores. */
static volatile u16 *const vga = (volatile u16 *)VGA_BASE;

static u16 vga_cell(char ch, u8 attr)
{
    return (u16)(((u16)attr << 8) | (u8)ch);
}

static void kputc(u32 row, u32 col, char ch, u8 attr)
{
    if (row >= VGA_ROWS || col >= VGA_COLS)
        return;
    vga[row * VGA_COLS + col] = vga_cell(ch, attr);
}

static void kputs(u32 row, u32 col, const char *s, u8 attr)
{
    while (*s) {
        kputc(row, col, *s, attr);
        s++;
        col++;
    }
}

/* print u64 as unsigned decimal - no printf anywhere in this OS */
static void kputu(u32 row, u32 col, u64 v, u8 attr)
{
    char buf[21];
    u32 i = 20;
    buf[i] = '\0';
    do {
        buf[--i] = (char)('0' + (u8)(v % 10u));
        v /= 10u;
    } while (v != 0);
    kputs(row, col, &buf[i], attr);
}

/* print u64 as 16 hex digits */
static void kputx(u32 row, u32 col, u64 v, u8 attr)
{
    static const char hex[] = "0123456789ABCDEF";
    u32 i;
    for (i = 0; i < 16; i++) {
        u32 shift = (16u - 1u - i) * 4u;
        kputc(row, col + i, hex[(v >> shift) & 0xFu], attr);
    }
}

static void kclear(u8 attr)
{
    u32 i;
    for (i = 0; i < VGA_COLS * VGA_ROWS; i++)
        vga[i] = vga_cell(' ', attr);
}

/* ---- functions gcc may EMIT CALLS to, even with -ffreestanding ------ */
void *memset(void *dst, int c, usize n)
{
    u8 *d = (u8 *)dst;
    while (n--)
        *d++ = (u8)c;
    return dst;
}

void *memcpy(void *dst, const void *src, usize n)
{
    u8 *d = (u8 *)dst;
    const u8 *s = (const u8 *)src;
    while (n--)
        *d++ = *s++;
    return dst;
}

void *memmove(void *dst, const void *src, usize n)
{
    u8 *d = (u8 *)dst;
    const u8 *s = (const u8 *)src;
    if (d < s) {
        while (n--)
            *d++ = *s++;
    } else {
        d += n;
        s += n;
        while (n--)
            *--d = *--s;
    }
    return dst;
}

/* ---- halting -------------------------------------------------------- */
static void halt_forever(void)
{
    for (;;)
        __asm__ volatile("cli; hlt");
}

/* ---- entry ---------------------------------------------------------- */
void kmain(void)
{
    u64 big;
    u32 *probe;

    kclear(ATTR_BLACK);

    kputs(0, 0, "hello from C in long mode", ATTR_WHITE);
    kputs(1, 0, "compiled by gcc, run by my own kernel", ATTR_GREEN);
    kputs(2, 0, "no libc, no stdint.h, no printf", ATTR_CYAN);

    /* 64-bit arithmetic: impossible with only 32-bit registers.
     * If this prints 4294967297, we really are in long mode. */
    big = 0xFFFFFFFFULL;
    big += 2;
    kputs(4, 0, "0xFFFFFFFF + 2 = ", ATTR_GREY);
    kputu(4, 17, big, ATTR_WHITE);

    /* pointers are 64-bit too: prove an address fits in u64 */
    probe = (u32 *)&big;
    kputs(5, 0, "address of big  = 0x", ATTR_GREY);
    kputx(5, 20, (u64)(uptr)probe, ATTR_WHITE);

    kputs(6, 0, "sizeof(u64) = ", ATTR_GREY);
    kputu(6, 14, (u64)sizeof(u64), ATTR_WHITE);

    kputs(8, 0, "kernel alive. halting.", ATTR_RED);

    halt_forever();
}