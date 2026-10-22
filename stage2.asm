[BITS 16]
[ORG 0x7E00]                ; loaded at 0x0000:0x7E00 -> labels ARE physical

start:
    cli
    xor ax, ax              ; DS = 0 so DS:offset == physical address
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