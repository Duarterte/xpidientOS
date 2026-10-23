/* types.h - the ONLY type definitions your kernel uses.
 * No libc, no stdint.h, no compiler headers: just typedefs of builtin types,
 * plus compile-time checks that they are the sizes x86-64 requires. */
#ifndef KERNEL_TYPES_H
#define KERNEL_TYPES_H

/* ---- fixed-width integers ------------------------------------------- */
typedef unsigned char      u8;    /* 1 byte  */
typedef signed   char      i8;

typedef unsigned short     u16;   /* 2 bytes */
typedef signed   short     i16;

typedef unsigned int       u32;   /* 4 bytes */
typedef signed   int       i32;

typedef unsigned long long u64;   /* 8 bytes */
typedef signed   long long i64;

/* ---- pointer-sized (LP64 on x86-64: long IS 64-bit) ------------------ */
typedef unsigned long      usize;
typedef signed   long      isize;

/* ---- common aliases -------------------------------------------------- */
typedef u64  uptr;                /* an address as an integer            */
typedef u8   bool8;               /* 0 = false, non-zero = true          */

#define NULL  ((void *)0)
#define true  1
#define false 0

/* ---- size checks: fail the BUILD if the target is not what we assume --
 * A negative array size is a compile error, so these are free asserts.  */
typedef char assert_u8_is_1  [(sizeof(u8)  == 1) ? 1 : -1];
typedef char assert_u16_is_2 [(sizeof(u16) == 2) ? 1 : -1];
typedef char assert_u32_is_4 [(sizeof(u32) == 4) ? 1 : -1];
typedef char assert_u64_is_8 [(sizeof(u64) == 8) ? 1 : -1];
typedef char assert_uptr_is_8[(sizeof(uptr) == 8) ? 1 : -1];

#endif /* KERNEL_TYPES_H */
