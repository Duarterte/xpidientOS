[BITS 16]
[ORG 0x0000]                ; loaded at offset 0 of segment 0x1000

start:
    cli
    mov ax, 0x1000          ; DS must match the LOAD SEGMENT
    mov ds, ax
    mov ss, ax
    mov sp, 0x7C00
    sti
    cld

    mov ax, 0xB800
    mov es, ax
    mov al, 0x0F            ; fill attribute: white on black
    call clear_vga

    mov si, msg
    xor di, di
    mov ah, 0x0A            ; light green on black
    call puts
    call sync_cursor        ; hardware cursor follows the text
    call halt

msg: db "Stage 2 loaded!", 0

%include "lib.asm"