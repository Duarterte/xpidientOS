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

    mov [boot_drive], dl    ; BIOS passes boot drive in DL - save it NOW

    mov ax, 0x1000          ; ES:BX = 0x1000:0000 = physical 0x10000
    mov es, ax
    xor bx, bx

    mov ah, 0x02            ; read sectors
    mov al, 1               ; how many
    mov ch, 0               ; cylinder
    mov cl, 2               ; sector (1-BASED! 2 = second sector = LBA 1)
    mov dh, 0               ; head
    mov dl, [boot_drive]
    int 0x13
    jc .error

    jmp 0x1000:0x0000       ; far jump: CS=0x1000, IP=0

.error:
    mov ax, 0xB800          ; int 0x13 left ES = 0x1000, so repoint to VGA
    mov es, ax
    mov si, errmsg
    xor di, di
    mov ah, 0x0F            ; white on black
    call puts
    call halt

boot_drive: db 0
errmsg:     db "Disk read error", 0

%include "lib.asm"          ; source-level share; bytes land inside this sector

times 510 - ($ - $$) db 0
dw 0xAA55