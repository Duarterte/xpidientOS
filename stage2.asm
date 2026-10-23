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
    cli
    in al, 0x92
    or al, 2
    out 0x92, al             ; A20 gate

    lgdt [gdtr]
    mov eax, cr0
    or eax, 1
    mov cr0, eax             ; CR0.PE
    jmp dword 0x08:pm32      ; far jump - no return

; ---- 16-bit data: never executed, only read ----
msg: db "Stage 2 loaded!", 0

gdt:
    dq 0x0000000000000000    ; 0x00 null descriptor (required)
    dq 0x00CF9A000000FFFF    ; 0x08 code: base 0, 4 GiB, 32-bit, readable
    dq 0x00CF92000000FFFF    ; 0x10 data: base 0, 4 GiB, writable
gdt_end:

gdtr:
    dw gdt_end - gdt - 1     ; limit = size - 1
    dd gdt                   ; linear base (physical, thanks to ORG 0x7E00)

idtr:
    dw 256*8 - 1             ; limit = 256 gates * 8 bytes - 1
    dd idt_table             ; linear base (physical, thanks to ORG 0x7E00)

%include "lib.asm"           ; MUST stay in the [BITS 16] region

; ---- 32-bit code ----
[BITS 32]
pm32:
    mov ax, 0x10             ; data selector - reload ALL of them
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, 0x90000         ; new stack, below VGA at 0xA0000

    call idt_setup           ; build 256 gates, then lidt
    call pic_remap           ; IRQ0..15 -> vectors 0x20..0x2F
    call pit_init            ; channel 0 at 100 Hz

    mov esi, pm_msg
    mov edi, 0xB8000 + 320   ; row 2, keeps row 0 visible
    mov ah, 0x0F             ; white on black
    call puts32

    mov esi, msg_timer
    mov edi, 0xB8000 + 640   ; row 4
    mov ah, 0x0E             ; yellow
    call puts32

    sti                      ; IDT + PIC are valid now, safe to enable
    mov byte [cur_attr], 0x0E      ; yellow, set ONCE - not inside the loop
.loop:
    mov eax, [tick]
    mov edi, 0xB8000 + 640 + 7*2   ; just after "Timer: "
    call print_u32
    hlt                      ; sleep until the next timer interrupt
    jmp .loop

; ---------------------------------------------------------------------------
; puts32 - 32-bit VGA writer
;   in:  ESI = string, EDI = 0xB8000 ofs, AH = attribute
;   out: EDI advanced past the text
;   clobbers: EAX, ESI, EDI   (DS must have base 0)
; ---------------------------------------------------------------------------
puts32:
    lodsb
    test al, al
    jz .done
    stosw
    jmp puts32
.done:
    ret

; ---------------------------------------------------------------------------
; idt_setup - fill all 256 gates with isr_default, then vector 0 = isr0
;   Every gate is 8 bytes:
;     +0 offset 15:0 | +2 CS | +4 zero | +5 type_attr | +6 offset 31:16
;   type_attr 0x8E = present, DPL 0, 32-bit INTERRUPT gate (clears IF)
; ---------------------------------------------------------------------------
idt_setup:
    mov edi, idt_table
    mov ecx, 256
    mov ebx, isr_default
.fill:
    mov eax, ebx
    mov [edi], ax            ; offset 15:0
    mov word [edi+2], 0x08   ; CS = code selector from the GDT
    mov byte [edi+4], 0      ; reserved, must be 0
    mov byte [edi+5], 0x8E   ; P=1 DPL=0 gate-type=0xE
    shr eax, 16
    mov [edi+6], ax          ; offset 31:16
    add edi, 8
    dec ecx
    jnz .fill

    mov edi, idt_table       ; vector 0 -> divide error handler
    mov eax, isr0
    mov [edi], ax
    shr eax, 16
    mov [edi+6], ax

    mov edi, idt_table + 0x20*8   ; vector 0x20 -> timer (IRQ0 after remap)
    mov eax, isr_timer
    mov [edi], ax
    shr eax, 16
    mov [edi+6], ax

    lidt [idtr]
    ret

; ---------------------------------------------------------------------------
; print_u32 - write EAX as unsigned decimal to ES:DI
;   in:  EAX = value, EDI = VGA offset
;        attribute taken from [cur_attr]  <- NOT from AH, because AH is part
;        of EAX and would corrupt the value being printed.
;   out: EDI advanced
;   clobbers: EAX, EBX, ECX, EDX
; ---------------------------------------------------------------------------
print_u32:
    push ebx
    push ecx
    push edx
    mov ecx, 10              ; divisor
    xor ebx, ebx             ; BL = digit count
    mov bh, [cur_attr]       ; BH = attribute (survives div)
.digits:
    xor edx, edx
    div ecx                  ; EAX = quotient, EDX = remainder
    add dl, '0'
    push edx                 ; digits come out reversed
    inc bl
    test eax, eax
    jnz .digits
.print:
    pop edx
    mov al, dl
    mov ah, bh
    stosw
    dec bl
    jnz .print
    pop edx
    pop ecx
    pop ebx
    ret

; ---------------------------------------------------------------------------
; pic_remap - move hardware IRQs off the CPU exception vectors
;   Without this, IRQ0 (timer) arrives on vector 0x08 = #DF = triple fault.
; ---------------------------------------------------------------------------
pic_remap:
    mov al, 0x11
    out 0x20, al             ; ICW1 master: init, ICW4 will follow
    out 0xA0, al             ; ICW1 slave

    mov al, 0x20
    out 0x21, al             ; ICW2 master: IRQ0..7  -> 0x20..0x27
    mov al, 0x28
    out 0xA1, al             ; ICW2 slave : IRQ8..15 -> 0x28..0x2F

    mov al, 0x04
    out 0x21, al             ; ICW3 master: slave is on IRQ2
    mov al, 0x02
    out 0xA1, al             ; ICW3 slave : cascade identity 2

    mov al, 0x01
    out 0x21, al             ; ICW4: 8086 mode
    out 0xA1, al

    mov al, 0xFE
    out 0x21, al             ; mask everything except IRQ0 (timer)
    mov al, 0xFF
    out 0xA1, al             ; slave fully masked
    ret

; ---------------------------------------------------------------------------
; pit_init - channel 0, mode 3, 100 Hz
;   1193182 / 100 = 11931 = 0x2E9B
; ---------------------------------------------------------------------------
pit_init:
    mov al, 0x36             ; ch0, lobyte/hibyte, mode 3, binary
    out 0x43, al
    mov ax, 11931
    out 0x40, al             ; low byte first
    mov al, ah
    out 0x40, al             ; then high byte
    ret

; ---------------------------------------------------------------------------
; isr_timer - IRQ0, vector 0x20. MUST return, MUST send EOI.
;   No EOI  -> the PIC never delivers IRQ0 again (one tick, then silence).
;   No iret -> the main loop never resumes.
; ---------------------------------------------------------------------------
isr_timer:
    push eax
    inc dword [tick]
    mov al, 0x20
    out 0x20, al             ; EOI to the master PIC
    pop eax
    iret

; ---------------------------------------------------------------------------
; isr0 - vector 0, divide error. The CPU pushes EIP, CS, EFLAGS - NO error
;        code. We do not return: halt and let the screen keep the evidence.
; ---------------------------------------------------------------------------
isr0:
    mov esi, msg_de
    mov edi, 0xB8000 + 480   ; row 3 - row 2 holds the PM message
    mov ah, 0x0C             ; light red
    call puts32
.h: cli
    hlt
    jmp .h

; ---------------------------------------------------------------------------
; isr_default - every other vector. Pushed frame differs per vector
;               (some push an error code) - which is why we never iret here.
; ---------------------------------------------------------------------------
isr_default:
    mov esi, msg_unk
    mov edi, 0xB8000 + 320
    mov ah, 0x0E             ; yellow
    call puts32
.h: cli
    hlt
    jmp .h

pm_msg:   db "Protected mode: 32-bit!", 0
msg_de:   db "EXCEPTION 0: divide error caught", 0
msg_unk:  db "EXCEPTION: unexpected vector", 0
msg_timer: db "Timer: ", 0

tick: dd 0                   ; incremented by isr_timer at 100 Hz
cur_attr: db 0x0F            ; current VGA attribute for print_u32

align 8
idt_table:
    times 256*8 db 0         ; 2048 bytes, filled at runtime by idt_setup