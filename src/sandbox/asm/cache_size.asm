global Read_32x2_Masked

section .text

; 64-bit Windows calling convention:
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
