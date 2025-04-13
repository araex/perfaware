global Write_x1
global Write_x2
global Write_x3
global Write_x4
global Write_x5

section .text

;
; NOTE(casey): These ASM routines are written for the Windows
; 64-bit ABI. They expect the count in rcx and the data pointer in rdx.
;

Write_x1:
	align 64
.loop:
    mov [rdx], rcx
    sub rcx, 1
    jnle .loop
    ret

Write_x2:
	align 64
.loop:
    mov [rdx], rcx
    mov [rdx], rcx
    sub rcx, 2
    jnle .loop
    ret

Write_x3:
	align 64
.loop:
    mov [rdx], rcx
    mov [rdx], rcx
    mov [rdx], rcx
    sub rcx, 3
    jnle .loop
    ret

Write_x4:
	align 64
.loop:
    mov [rdx], rcx
    mov [rdx], rcx
    mov [rdx], rcx
    mov [rdx], rcx
    sub rcx, 4
    jnle .loop
    ret

Write_x5:
	align 64
.loop:
    mov [rdx], rcx
    mov [rdx], rcx
    mov [rdx], rcx
    mov [rdx], rcx
    mov [rdx], rcx
    sub rcx, 5
    jnle .loop
    ret