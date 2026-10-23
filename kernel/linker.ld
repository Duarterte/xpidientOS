ENTRY(_start)

SECTIONS
{
    . = 0x100000;               /* the kernel's virtual/physical base */

    .text : ALIGN(16) {
        *(.text.entry)          /* _start FIRST - the jump target is byte 0 */
        *(.text*)
    }

    .rodata : ALIGN(16) {
        *(.rodata*)
    }

    .data : ALIGN(16) {
        *(.data*)
    }

    .bss : ALIGN(16) {
        __bss_start = .;
        *(COMMON)
        *(.bss*)
        __bss_end = .;
    }

    __kernel_end = .;
}