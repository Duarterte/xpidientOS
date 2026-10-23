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
    mov ax, 0x2F00          ; also publish it at 0x2F000 for stage2:
    mov es, ax              ;   0x0500-0x051F is SeaBIOS scratch and gets
    mov [es:0], dl          ;   clobbered, 0x2F000 is untouched free RAM

    mov ax, 0x0000          ; ES:BX = 0x0000:0x7E00 = physical 0x7E00
    mov es, ax
    mov bx, 0x7E00          ; MOV, not xor - bx holds the offset

    mov ah, 0x02            ; read sectors
    mov al, 8               ; how many (stage2 is padded to whole sectors)
    mov ch, 0               ; cylinder
    mov cl, 2               ; sector (1-BASED! 2 = second sector = LBA 1)
    mov dh, 0               ; head
    mov dl, [boot_drive]
    int 0x13
    jc .error

    jmp 0x0000:0x7E00       ; far jump: CS=0, IP=0x7E00

.error:
    mov ax, 0xB800          ; int 0x13 left ES = 0, so repoint to VGA
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