extern Funny_c
global Funny_asm
section .text

; rdi *src
; rsi *dst
; edx width
; ecx height
; r8d src_row_size
; r9d dst_row_size
Funny_asm:
push rbp
mov rbp, rsp

movdqu xmm8, [mask_shift_right1]
movdqu xmm9, [mask_opacity]
movdqu xmm10, [mask_half_xmm]
movdqu xmm11, [float_tens]
movdqu xmm12, [double_tens]
movdqu xmm13, [float_hundreeds]
movdqu xmm14, [int_ones]
movdqu xmm15, [int_hundreeds]

xor r10, r10  ; j = 0
xor r11, r11  ; i = 0

.loop:

    pxor xmm0,xmm0
    pxor xmm1,xmm1

    ; set j's to xmm0: xmm0 = [ 0 | 0 | 0 | j+3 | 0 | 0 | 0 | j+2 | 0 | 0 | 0 | j+1 | 0 | 0 | 0 | j ]
    pinsrw xmm0, r10w, 0
    inc r10
    pinsrw xmm0, r10w, 2
    inc r10
    pinsrw xmm0, r10w, 4
    inc r10
    pinsrw xmm0, r10w, 6

    ; set i's to xmm1: xmm1 = [ 0 | 0 | 0 | i | 0 | 0 | 0 | i | 0 | 0 | 0 | i | 0 | 0 | 0 | i ]
    pinsrw xmm1, r11w, 0
    packusdw xmm1, xmm1
    packusdw xmm1, xmm1

    ; Fetch from mem
    movdqu xmm5, [rdi]      ; xmm5 = [ ARGB 4 | ARGB 3 | ARGB 2 | ARGB 1 ]

    call calcFunnyR
    call calcFunnyG
    call calcFunnyB

    ; xmm5 /= 2
    psrlw xmm5, 1
    pand xmm5, xmm8 ; xmm8 = [mask_shift_right1]

    ; xmm5 += xmm2 / 2
    psrlw xmm2, 1
    pand xmm2, xmm8 ; xmm8 = [mask_shift_right1]
    paddusb xmm5, xmm2

    ; xmm5 += xmm3 / 2
    psrlw xmm3, 1
    pand xmm3, xmm8 ; xmm8 = [mask_shift_right1]
    paddusb xmm5, xmm3

    ; xmm5 += xmm4 / 2
    psrlw xmm4, 1
    pand xmm4, xmm8 ; xmm8 = [mask_shift_right1]
    paddusb xmm5, xmm4

    por xmm5, xmm9; xmm9 = [mask_opacity] (undo the shift right on the opacity)

    ; Save to mem
    movdqu [rsi], xmm5

    ; loop j
    add rdi, 4*4
    add rsi, 4*4
    inc r10
    cmp r10d, edx
    jne .loop

    ; loop i
    xor r10, r10
    inc r11
    cmp r11d, ecx
    jne .loop

pop rbp
ret

; NOT to be called from C
; params: xmm0: 2 8 bit ints "j" -> preserved
;         xmm1: 2 8 bit ints "i" -> preserved
; returns: xmmm2 = [ 0 | r4 | 0 | 0 | 0 | r3 | 0 | 0 | 0 | r2 | 0 | 0 | 0 | r1 | 0 | 0 ]
; modifies xmm6
calcFunnyR:
    movdqa xmm2, xmm1

    psubd xmm2, xmm0
    pabsd xmm2, xmm2

    cvtdq2ps xmm2, xmm2
    sqrtps xmm2, xmm2

    movdqu xmm6, xmm13      ; xmm13 = [float_hundreeds]

    mulps xmm2, xmm6

    cvttps2dq xmm2, xmm2

    pslldq xmm2, 2

    movdqu xmm6, xmm9       ; xmm9 = [mask_opacity]
    psrldq xmm6, 1
    pand xmm2, xmm6         ; xmm6 = [mask_R]
    ret


; NOT to be called from C
; params: xmm0: 2 8 bit ints "j" -> preserved
;         xmm1: 2 8 bit ints "i" -> preserved
; returns: xmmm3 = [ 0 | 0 | g4 | 0 | 0 | 0 | g3 | 0 | 0 | 0 | g2 | 0 | 0 | 0 | g1 | 0 ]
; modifies xmm6, xmm7
calcFunnyG:
    movdqa xmm3, xmm1
    movdqa xmm6, xmm1

    psubsw xmm3, xmm0
    pabsw xmm3, xmm3
    cvtdq2ps xmm3, xmm3
    movdqu xmm7, xmm11      ; xmm11 =[float_tens]
    mulps xmm3, xmm7

    paddsw xmm6, xmm0
    movdqu xmm7, xmm14      ; xmm14 = [int_ones]
    paddsw xmm6, xmm7
    cvtdq2ps xmm6, xmm6
    movdqu xmm7, xmm13      ; xmm13 = [float_hundreeds]
    divps xmm6, xmm7

    divps xmm3, xmm6

    cvttps2dq xmm3, xmm3

    pslldq xmm3, 1

    movdqu xmm6, xmm9       ; xmm9 = [mask_opacity]
    psrldq xmm6, 2
    pand xmm3, xmm6         ; xmm6 = [mask_G]
    ret

; NOT to be called from C
; params: xmm0: 2 8 bit ints "j" -> preserved
;         xmm1: 2 8 bit ints "i" -> preserved
; returns: xmmm4 = [ 0 | 0 | 0 | b4 | 0 | 0 | 0 | b3 | 0 | 0 | 0 | b2 | 0 | 0 | 0 | b1 ]
; modifies xmm6, xmm7
calcFunnyB:
    movdqa xmm4, xmm1
    pslld xmm4, 1
    movdqa xmm6, xmm0
    pslld xmm6, 1

    movdqu xmm7, xmm15      ; xmm15 = [int_hundreeds]
    paddsw xmm4, xmm7
    paddsw xmm6, xmm7

    cvtdq2ps xmm4, xmm4
    cvtdq2ps xmm6, xmm6

    mulps xmm4, xmm6

    movdqa xmm6, xmm4
    psrldq xmm6, 8
    cvtps2pd xmm4, xmm4
    cvtps2pd xmm6, xmm6

    sqrtpd xmm4, xmm4
    sqrtpd xmm6, xmm6

    movdqu xmm7, xmm12      ; xmm12 = [double_tens]
    mulpd xmm4, xmm7
    mulpd xmm6, xmm7

    cvttpd2dq xmm4, xmm4
    cvttpd2dq xmm6, xmm6
    pand xmm4, xmm10        ; xmm10 = [mask_half_xmm]
    pslldq xmm6, 8
    paddw xmm4,xmm6

    movdqu xmm6, xmm9       ; xmm9 = [mask_opacity]
    psrldq xmm6, 3
    pand xmm4, xmm6         ; xmm6 = [mask_B]
    ret


section .rodata
align 16
mask_shift_right1: times 16  db 0xff >> 1
mask_opacity: times 4 dd 0xff000000
mask_half_xmm: dd 0xFFFFFFFF, 0xFFFFFFFF, 0x00000000, 0x00000000
mask_R: times 4 dd 0x00ff0000
mask_G: times 4 dd 0x0000ff00
mask_B: times 4 dd 0x000000ff
float_tens: times 4 dd 10.0
double_tens: times 2 dq 10.0
float_hundreeds: times 4 dd 100.0
int_ones: times 4 dd 1
int_hundreeds: times 4 dd 100