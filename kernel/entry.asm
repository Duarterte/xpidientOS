[BITS 64]

global _start
extern kmain
extern __bss_start
extern __bss_end

section .text.entry
_start:
    cli                         ; no interrupts exist yet: no IDT, no handlers
    mov rsp, stack_top          ; the stack C will use
    xor rbp, rbp                ; mark the outermost frame

    ; zero .bss: it is NOT in the binary, so it holds garbage right now
    mov rdi, __bss_start
    mov rcx, __bss_end
    sub rcx, rdi                ; byte count
    xor eax, eax
    cld
    rep stosb

    call kmain                  ; never returns by contract

.hang:
    cli
    hlt
    jmp .hang

section .bss
align 16
stack_bottom:
    resb 16384                  ; 16 KiB, zeroed by the loop above
stack_top: