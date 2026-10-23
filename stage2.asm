; ===========================================================================
; stage2.asm - stage 2.  No output, no IDT, no PIC, no PIT.
;   1. read the kernel from LBA 64 into a low staging buffer
;   2. enable A20, load a GDT, enter 32-bit protected mode
;   3. copy the kernel to 0x100000, build page tables, enter long mode
;   4. jump to 0x100000 - everything after that is C
; ===========================================================================
[BITS 16]
[ORG 0x7E00]                    ; loaded at 0x0000:0x7E00, so labels ARE physical

%define DRIVE_SEG    0x2F00     ; :0 holds the boot drive number from stage1
%define KERNEL_LBA   64         ; frozen contract: kernel image starts here
%define KERNEL_SECS  64         ; 32 KiB
%define STAGE_BUF    0x30000    ; low staging buffer (BIOS cannot write above 1 MiB)
%define KERNEL_DEST  0x100000   ; where the kernel must actually run

start:
    cli
    xor ax, ax
    mov ds, ax
    mov ss, ax
    mov sp, 0x7C00
    sti
    cld

    call load_kernel

    cli
    in al, 0x92                 ; A20 gate open
    or al, 2
    out 0x92, al

    lgdt [gdtr]
    mov eax, cr0
    or eax, 1                   ; CR0.PE
    mov cr0, eax
    jmp dword 0x08:pm32         ; far jump - CS comes from the GDT

; ---------------------------------------------------------------------------
; load_kernel - int 0x13 AH=0x42, Disk Address Packet -> 0x30000
; ---------------------------------------------------------------------------
load_kernel:
    mov word  [dap + 0],  16              ; packet size
    mov word  [dap + 1],  0               ; reserved
    mov word  [dap + 2],  KERNEL_SECS     ; sector count
    mov word  [dap + 4],  0x0000          ; buffer offset
    mov word  [dap + 6],  0x3000          ; buffer segment -> 0x30000
    mov dword [dap + 8],  KERNEL_LBA      ; LBA low
    mov dword [dap + 12], 0               ; LBA high

    push ds
    mov ax, DRIVE_SEG
    mov ds, ax
    mov dl, [0]
    pop ds

    mov si, dap
    mov ah, 0x42
    int 0x13
    jc .error
    ret

.error:
    mov ax, 0xB800              ; red 'E' in the top-left corner
    mov es, ax
    mov ax, 0x0C45
    mov [es:0], ax
    cli
.h: hlt
    jmp .h

align 4
dap:
    times 16 db 0

; ---- data (never executed) ----
gdt:
    dq 0x0000000000000000       ; 0x00 null descriptor (required)
    dq 0x00CF9A000000FFFF       ; 0x08 code 32-bit (D=1)
    dq 0x00CF92000000FFFF       ; 0x10 data
    dq 0x00AF9A000000FFFF       ; 0x18 code 64-bit (L=1, D=0)
gdt_end:

gdtr:
    dw gdt_end - gdt - 1
    dd gdt                      ; linear base = physical, thanks to ORG 0x7E00

; ===========================================================================
[BITS 32]
pm32:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, 0x90000            ; 16-byte aligned stack, below VGA at 0xA0000

    call copy_kernel            ; 0x30000 -> 0x100000
    call build_pagetables       ; identity map 4 GiB with 2 MiB pages
    jmp enter_long              ; never returns

; ---------------------------------------------------------------------------
; copy_kernel - rep movsd KERNEL_SECS*512 bytes from staging to 0x100000
; ---------------------------------------------------------------------------
copy_kernel:
    cld
    mov esi, STAGE_BUF
    mov edi, KERNEL_DEST
    mov ecx, (KERNEL_SECS * 512) / 4
    rep movsd
    ret

; ---------------------------------------------------------------------------
; build_pagetables - PML4 @0x20000, PDPT @0x21000, 4 PDs @0x22000..0x25000
; ---------------------------------------------------------------------------
build_pagetables:
    push eax
    push ecx
    push edi

    mov edi, 0x20000            ; clear all 24 KiB
    mov ecx, 0x6000/4
    xor eax, eax
    rep stosd

    mov dword [0x20000], 0x21000 | 3          ; PML4[0] -> PDPT
    mov dword [0x21000 + 0*8], 0x22000 | 3    ; PDPT[0..3] -> 4 PDs
    mov dword [0x21000 + 1*8], 0x23000 | 3
    mov dword [0x21000 + 2*8], 0x24000 | 3
    mov dword [0x21000 + 3*8], 0x25000 | 3

    mov edi, 0x22000
    mov eax, 0x000000 | 0x83    ; first entry maps physical 0, PS=huge page
    mov ecx, 2048               ; 2048 * 2 MiB = 4 GiB
.fill:
    mov [edi], eax
    add eax, 0x200000
    add edi, 8
    dec ecx
    jnz .fill

    pop edi
    pop ecx
    pop eax
    ret

; ---------------------------------------------------------------------------
; enter_long - 32-bit protected mode -> IA-32e.  Order is mandatory.
; ---------------------------------------------------------------------------
enter_long:
    mov eax, 0x80000000         ; is long mode available at all?
    cpuid
    cmp eax, 0x80000001
    jb .no_lm
    mov eax, 0x80000001
    cpuid
    test edx, 1 << 29
    jz .no_lm

    mov eax, 0x20000            ; CR3 = physical address of PML4
    mov cr3, eax

    mov eax, cr4
    or eax, 1 << 5              ; CR4.PAE (long mode is a PAE extension)
    mov cr4, eax

    mov ecx, 0xC0000080         ; IA32_EFER
    rdmsr
    or eax, (1 << 8) | (1 << 11) ; LME | NXE
    xor edx, edx
    wrmsr

    mov eax, cr0
    or eax, 0x80000001          ; PG + PE together activate long mode
    mov cr0, eax

    jmp 0x18:pm64               ; far jump - validates the L=1 descriptor

.no_lm:
    mov ax, 0xB800              ; red 'L' in the top-left corner
    mov es, ax
    mov ax, 0x0C4C
    mov [es:0], ax
    cli
.h: hlt
    jmp .h

; ===========================================================================
[BITS 64]
pm64:
    mov ax, 0x10                ; data selectors (validated, then ignored)
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov rsp, 0x90000

    mov rax, KERNEL_DEST
    jmp rax                     ; -> _start in the C kernel, never returns
