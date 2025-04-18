global Read_32x2_Masked
global Read_32x8_RepCount

section .text

; Routines in this file use 64-bit Windows calling convention

; rcx: total number of bytes to read. Must be evenly divisible by 64
; rdx: data pointer
;  r8: mask for read offsets
Read_32x2_Masked:
    xor rax, rax
	align 64
.loop:
    ; apply the mask for the read offset
    mov r9, rax
    and r9, r8
    vmovdqu ymm0, [rdx + r9]
    vmovdqu ymm0, [rdx + r9 + 32]

    ; advance
    add rax, 64
    cmp rax, rcx
    jb .loop
    ret

; rcx: repetition count
; rdx: data pointer
;  r8: bytes to read per repetition
Read_32x8_RepCount:
.outer:
    xor rax, rax
    .inner:
        vmovdqu ymm0, [rdx + rax]
        vmovdqu ymm0, [rdx + rax + 32]
        vmovdqu ymm0, [rdx + rax + 64]
        vmovdqu ymm0, [rdx + rax + 96]
        vmovdqu ymm0, [rdx + rax + 128]
        vmovdqu ymm0, [rdx + rax + 160]
        vmovdqu ymm0, [rdx + rax + 192]
        vmovdqu ymm0, [rdx + rax + 224]

        ; advance
        add rax, 256
        cmp rax, r8
        jb .inner
    
    ; advance
    dec rcx
    jnz .outer

ret
