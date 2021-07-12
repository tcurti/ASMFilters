global Gamma_asm

;void Gamma_asm (uint8_t *src, uint8_t *dst, int width, int height, int src_row_size, int dst_row_size);
; rdi <- &src
; rsi <- &dst
; edx <- ancho
; ecx <- alto
; r8d  <- src_tam_fila
; r9d  <- dst_tam_fila

section .rodata
coeficiente: DD 255.0, 255.0, 255.0, 255.0
mascara: DD 0xFF000000, 0xFF000000, 0xFF000000, 0xFF000000

section .text

Gamma_asm:
	;armado de stackframe
	push rbp
	mov rbp, rsp

	mov eax, edx
	mul ecx

	; cantidad de iteraciones
	shl rdx, 32
	or  rdx, rax
	shr rdx, 2

	; seteamos indices y mascaras
	movups xmm7, [coeficiente]
	movdqu xmm8, [mascara]

	.ciclo:
		; Conseguimos los datos para la nueva matriz

		movdqu xmm12, [rdi]			; xmm12:|t3|r3|g3|b3|t2|r2|g2|b2|t1|r1|g1|b1|t0|r0|g0|b0| (Bytes)

		; 1er Pixel
		pmovzxbd xmm3, xmm12				; xmm3:	|A0|R0|G0|B0| (dwords)
		cvtdq2ps xmm3, xmm3					; xmm3: |A0|R0|G0|B0| (singles)
		divps xmm3, xmm7					; xmm3: |A0/255|R0/255|G0/255|B0/255|
		sqrtps xmm3, xmm3					; xmm3: |sqrt(A0/255)|sqrt(R0/255)|sqrt(G0/255)|sqrt(B0/255)|
		mulps xmm3, xmm7					; xmm3: |255*sqrt(A0/255)|255*sqrt(R0/255)|255*sqrt(G0/255)|255*sqrt(B0/255)|
		cvttps2dq xmm3, xmm3				; xmm3 : Pixel 1


		; 2do Pixel
		psrldq xmm12, 4						; xmm12:|00|00|00|00|a3|r3|g3|b3|a2|r2|g2|b2|a1|r1|g1|b1| (Bytes)
		pmovzxbd xmm4, xmm12				; xmm4: |A1|R1|G1|B1| (dword)
		cvtdq2ps xmm4, xmm4				; xmm4: |A1|R1|G1|B1| (singles)
		divps xmm4, xmm7					; xmm4: |A1/255|R1/255|G1/255|B1/255|
		sqrtps xmm4, xmm4					; xmm4: |sqrt(A1/255)|sqrt(R1/255)|sqrt(G1/255)|sqrt(B1/255)|
		mulps xmm4, xmm7					; xmm4: |255*sqrt(A1/255)|255*sqrt(R1/255)|255*sqrt(G1/255)|255*sqrt(B1/255)|
		cvttps2dq xmm4, xmm4					; xmm4: Pixel 2
		packusdw xmm3, xmm4					; 1er paquete

		; 3er Pixel
		psrldq xmm12, 4						; xmm12:|00|00|00|00|00|00|00|00|a3|r3|g3|b3|a2|r2|g2|b2| (Bytes)
		pmovzxbd xmm4, xmm12				; xmm4:	|A2|R2|G2|B2| (dwords)
		cvtdq2ps xmm4, xmm4				; xmm4: |A2|R2|G2|B2| (singles)
		divps xmm4, xmm7					; xmm4: |A2/255|R2/255|G2/255|B2/255|
		sqrtps xmm4, xmm4					; xmm4: |sqrt(A2/255)|sqrt(R2/255)|sqrt(G2/255)|sqrt(B2/255)|
		mulps xmm4, xmm7					; xmm4: |255*sqrt(A2/255)|255*sqrt(R2/255)|255*sqrt(G2/255)|255*sqrt(B2/255)|
		cvttps2dq xmm4, xmm4					; xmm4: pixel 3

		; 4to pixel
		psrldq xmm12, 4						; xmm12:|00|00|00|00|00|00|00|00|00|00|00|00|a3|r3|g3|b3| (Bytes)
		pmovzxbd xmm5, xmm12				; xmm5: |A3|R3|G3|B3| (dword)
		cvtdq2ps xmm5, xmm5					; xmm5: |A3|R3|G3|B3| (singles)
		divps xmm5, xmm7					; xmm3: |A3/255|R3/255|G3/255|B3/255|
		sqrtps xmm5, xmm5 					; xmm3: |sqrt(A3/255)|sqrt(R3/255)|sqrt(G3/255)|sqrt(B3/255)|
		mulps xmm5, xmm7					; xmm3: |255*sqrt(A3/255)|255*sqrt(R3/255)|255*sqrt(G3/255)|255*sqrt(B3/255)|
		cvttps2dq xmm5, xmm5					; xmm5: pixel 4
		packusdw xmm4, xmm5					    ; 2do paquete

		; empaquetamos
		packuswb xmm3, xmm4					; xmm3 = 4 píxeles resultado
		; seteamos transparencias en 255
		por xmm3, xmm8
		; movemos a memoria
		movdqu [rsi], xmm3

		; proximo ciclo
		add rsi, 4 * 4
		add rdi, 4 * 4
		dec rdx
		jnz .ciclo

	; desarmo stackframe
	pop rbp
	ret
