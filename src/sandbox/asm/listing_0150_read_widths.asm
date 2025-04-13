;  ========================================================================
;
;  (C) Copyright 2023 by Molly Rocket, Inc., All Rights Reserved.
;
;  This software is provided 'as-is', without any express or implied
;  warranty. In no event will the authors be held liable for any damages
;  arising from the use of this software.
;
;  Please see https://computerenhance.com for more information
;
;  ========================================================================

;  ========================================================================
;  LISTING 150
;  ========================================================================

global Read_4x3
global Read_8x3
global Read_16x2
global Read_16x3
global Read_32x2
global Read_32x3

section .text

;
; NOTE(casey): These ASM routines are written for the Windows
; 64-bit ABI. They expect RCX to be the first parameter (the count),
; and in the case of MOVAllBytesASM, RDX to be the second
; parameter (the data pointer). To use these on a platform
; with a different ABI, you would have to change those registers
; to match the ABI.
;

Read_4x3:
    xor rax, rax
	align 64
.loop:
    mov r8d, [rdx ]
    mov r8d, [rdx + 4]
    mov r8d, [rdx + 8]
    add rax, 12
    cmp rax, rcx
    jb .loop
    ret

Read_8x3:
    xor rax, rax
	align 64
.loop:
    mov r8, [rdx ]
    mov r8, [rdx + 8]
    mov r8, [rdx + 16]
    add rax, 24
    cmp rax, rcx
    jb .loop
    ret

Read_16x2:
    xor rax, rax
	align 64
.loop:
    vmovdqu xmm0, [rdx]
    vmovdqu xmm0, [rdx + 16]
    add rax, 32
    cmp rax, rcx
    jb .loop
    ret

Read_16x3:
    xor rax, rax
	align 64
.loop:
    vmovdqu xmm0, [rdx]
    vmovdqu xmm0, [rdx + 16]
    vmovdqu xmm0, [rdx + 32]
    add rax, 48
    cmp rax, rcx
    jb .loop
    ret

Read_32x2:
    xor rax, rax
	align 64
.loop:
    vmovdqu ymm0, [rdx]
    vmovdqu ymm0, [rdx + 32]
    add rax, 64
    cmp rax, rcx
    jb .loop
    ret

Read_32x3:
    xor rax, rax
	align 64
.loop:
    vmovdqu ymm0, [rdx]
    vmovdqu ymm0, [rdx + 32]
    vmovdqu ymm0, [rdx + 64]
    add rax, 96
    cmp rax, rcx
    jb .loop
    ret
