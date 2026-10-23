; ===========================================================================
; boot.asm - stage 1.  Exactly 512 bytes.  One job: load stage 2 and jump.
; ===========================================================================
[BITS 16]
[ORG 0x7C00]

start:
    jmp 0x0000:main

main:
    cli
    xor ax, ax
    mov ds, ax
    mov ss, ax
    mov sp, 0x7C00
    sti
    cld

    mov [boot_drive], dl        ; save the BIOS drive number
    mov ax, 0x2F00              ; publish it where stage2 can see it
    mov es, ax                  ; (0x0500 is SeaBIOS scratch - do not use)
    mov [es:0], dl

    mov ax, 0x0000
    mov es, ax
    mov bx, 0x7E00              ; ES:BX = 0x0000:0x7E00

    mov ah, 0x02                ; read sectors
    mov al, 8                   ; 8 sectors = 4 KiB of stage2
    mov ch, 0
    mov cl, 2                   ; CHS is 1-based: sector 2 = LBA 1
    mov dh, 0
    mov dl, [boot_drive]
    int 0x13
    jc .error

    jmp 0x0000:0x7E00           ; far jump: reload CS, no return

.error:
    mov ax, 0xB800              ; red 'E' in the top-left corner
    mov es, ax
    mov ax, 0x0C45
    mov [es:0], ax
    cli
.h: hlt
    jmp .h

boot_drive: db 0

    times 510 - ($ - $$) db 0
    dw 0xAA55
