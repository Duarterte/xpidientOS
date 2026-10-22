; lib.asm - shared 16-bit real-mode helpers
; Pulled in with %include from boot.asm and stage2.asm.
; NASM COPIES the text at assembly time, so each binary gets its own copy
; (there is no linker, no shared symbols between the two .bin files).
;
; RULES: no [BITS], no [ORG], no binary-specific data in this file.
;        Nothing here may depend on a particular load address.
; PREREQ: caller must have done `cld` (DF=0) - rep stosw follows DF.

; ---------------------------------------------------------------------------
; puts - write a NUL-terminated string into VGA text memory
;   in:  DS:SI = string
;        ES:DI = offset into 0xB800 segment (already computed by caller)
;        AH    = attribute byte (0x0F white, 0x0A green, ...)
;   out: DI advanced past the last character
;   clobbers: AL, SI, DI
; ---------------------------------------------------------------------------
puts:
    lodsb                   ; AL = [DS:SI], SI++
    test al, al             ; NUL terminator?
    jz .done
    stosw                   ; [ES:DI] = AX (AL=char, AH=attr), DI += 2
    jmp puts
.done:
    ret

; ---------------------------------------------------------------------------
; clear_vga - blank the 80x25 text screen
;   in:  ES = 0xB800
;        AL = fill attribute
;   out: DI = 0
;   clobbers: AX, CX, DI
; ---------------------------------------------------------------------------
clear_vga:
    mov ah, al              ; AH = attribute
    mov al, ' '             ; AL = space (0x20)
    xor di, di              ; start at cell 0
    mov cx, 2000            ; 80 * 25 cells
    rep stosw               ; DI ends at 4000 -> reset it
    xor di, di
    ret

; ---------------------------------------------------------------------------
; sync_cursor - move the blinking hardware cursor to DI's position
;   in:  DI = offset into 0xB800 memory (must be even)
;   out: nothing
;   Uses VGA CRTC ports 0x3D4 (index) / 0x3D5 (data)
; ---------------------------------------------------------------------------
sync_cursor:
    push ax
    push bx
    push dx

    mov bx, di
    shr bx, 1               ; bx = row*80 + col (cell index, not byte offset)

    mov dx, 0x3D4
    mov al, 0x0F            ; cursor location low byte
    out dx, al
    inc dx
    mov al, bl
    out dx, al

    dec dx
    mov al, 0x0E            ; cursor location high byte
    out dx, al
    inc dx
    mov al, bh
    out dx, al

    pop dx
    pop bx
    pop ax
    ret

; ---------------------------------------------------------------------------
; halt - stop the CPU forever
;   never returns
; ---------------------------------------------------------------------------
halt:
    cli
.hang:
    hlt                     ; sleeps until an interrupt; interrupts are off
    jmp .hang               ; safety net
