global Max_asm

section .rodata

ALIGN   16
alpha_filter: times 2 dq 0x0000FFFFFFFFFFFF ; | 0000 | FFFF | FFFF | FFFF | 0000 | FFFF | FFFF | FFFF |

section .text

%define pixel_size 4


; void Max_asm(uint8_t *src, uint8_t *dst, int width, int height,
;                      int src_row_size, int dst_row_size);
Max_asm:
    push rbp
    mov  rbp, rsp

    ; rdi = *src
    ; rsi = *dst
    ; edx = width
    ; ecx = height
    ; r8d = src_row_size = dst_row_size
    ; r9d = dst_row_size

    %define width        rdx
    %define src_col_ptr  rsi
    %define dst_col_ptr  rdi
    %define img_row_size r9
    %define height       r10
    %define dst_row_ptr  r11

    mov  height, rcx

    xchg rdi, rsi ; rdi = rsi ; rsi = rdi
    mov dst_row_ptr, dst_col_ptr

    ; Extiendo parametros a 64b
    mov	r9d, r9d   ; img_row_size
    mov	r10d, r10d ; height
    mov edx, edx   ; width

    ; Cantidad de columnas a iterar
    shr width, 2
    dec width
    ; Cantidad de filas de 2 de alto
    shr height, 1 
    dec height

    movdqa xmm15, [alpha_filter]

    ; Pinto el borde superior de la primera columna
    pcmpeqq xmm0, xmm0
    movdqu  [dst_row_ptr], xmm0

    .ciclo_columna:
        lea dst_row_ptr, [dst_col_ptr + img_row_size + pixel_size] ; Apunto a los pixeles que se van a escribir

        pxor    xmm10, xmm10 ; Seteo como maximos iniciales, a los pixeles 0 

        ; Calculo el max entre las primeras dos filas de cada bloque.
        mov  rax, src_col_ptr
        call hallarMaxDeLaFila
        lea  rax, [rax + img_row_size]
        call hallarMaxDeLaFila
        ; xmm10 contiene el resultado del bloque 1 en la parte baja, y el del bloque 2 en la alta

        movdqu  xmm11, xmm10 ; guardo el resultado en xmm11

        mov rcx, height
        .ciclo_bloque:
            pxor    xmm10, xmm10 ; seteo los max en 0

            ; Calculo los max de las siguientes dos filas de cada bloque
            lea  rax, [rax + img_row_size]
            call hallarMaxDeLaFila
            lea  rax, [rax + img_row_size]
            call hallarMaxDeLaFila

            movdqu  xmm12, xmm10         ; guardo temp. max ultimas dos filas

            ; calculo max de las ultimas 4 filas comparando con los max anteriores
            movdqu   xmm4, xmm10         ; coloco candidato a max en xmm4
            movdqu  xmm10, xmm11         ; coloco max anterior en xmm10
            movdqu  xmm11, xmm12         ; guardo el max de las ultimas 2 filas en xmm11
            call actualizarMax           ; xmm10 = |        max2 |        max1 |

            ; Pack de los max:
            pand     xmm10, xmm15        ; Borro la suma tot. de cada pix. que se encuentra en la posición del alpha
            pcmpeqd   xmm0, xmm0
            pxor      xmm0, xmm15
            psrlw     xmm0, 1
            paddw    xmm10, xmm0         ; coloco 1's en la componente alpha 
            packuswb xmm10, xmm10
            pshufd   xmm10, xmm10, 0x0F  ; xmm10 = | max2 | max2 | max1 | max1 |

            ; Escritura en destino
            movdqu   [dst_row_ptr], xmm10                     ; dst_row_ptr -> | max1 | max1 | max2 | max2 |
            movdqu   [dst_row_ptr + img_row_size], xmm10      ; sig. fila   -> | max1 | max1 | max2 | max2 |

            lea dst_row_ptr, [dst_row_ptr + 2 * img_row_size] ; bajo dos filas
            loop .ciclo_bloque

        ; Pinto borde inferior columna
        pcmpeqq  xmm0, xmm0
        movdqu   [dst_row_ptr - pixel_size], xmm0

        ; Avanzo a la siguiente columna
        lea dst_col_ptr, [dst_col_ptr + 4 * pixel_size]
        lea src_col_ptr, [src_col_ptr + 4 * pixel_size]

        ; Pinto borde superior columna
        movdqu   [dst_col_ptr - 1 * pixel_size], xmm0

        dec width
        cmp width, 0
        jg .ciclo_columna      ; Caso: siguiente columna
        jl .padding_horizontal ; Caso: fin
        ; Caso: última columna

        ; Pinto último borde inferior columna
        movdqu   [dst_row_ptr + 3 * pixel_size], xmm0

        ; Como el algoritmo calcula de a dos bloques, se da que en la ultima columna es
        ; necesario retroceder para calcular en la última pasada de a un bloque.
        lea dst_col_ptr, [dst_col_ptr - 2 * pixel_size]
        lea src_col_ptr, [src_col_ptr - 2 * pixel_size]
        lea dst_row_ptr, [dst_col_ptr]
        jmp .ciclo_columna

    ; Finalmente pinto los bordes de los costados
    .padding_horizontal:
        shl height, 1
        mov rcx, height
        .ciclo_padding_h:
            ; Se aprovecha que el último pixel de una fila es consecutivo del primero de la siguiente.
            movq [dst_col_ptr + img_row_size + pixel_size], xmm0
            lea dst_col_ptr, [dst_col_ptr + img_row_size]
            loop .ciclo_padding_h
    
    pop rbp
    ret


; Se traen 6 pixeles consecutivos de la direccion que se pase en rax.
; Los 4 primeros corresponden a los pixeles A, B, C y D de la fila de un bloque.
; Los 4 últimos serían los pixeles A', B', C' y D' de la fila del bloque consecutivo al anterior (el de la derecha).
; En el registro xmm10, se espera que estén los max de la fila anterior.
; Se calcula el max de cada fila y finalmente se los compara con los compara con los max en el registro xmm10
; Se devuelve el max actualizado en xmm10
hallarMaxDeLaFila:
    ; Traigo los 6 pixeles y los guardo en los registros xmm1,2,3 con sus componentes extendidas a 16bit
    movdqu   xmm2, [rax]                  ; xmm2 = |  D  |  C  |  B  |  A  |
    pmovzxbw xmm1, xmm2                   ; xmm1 = |        B  |        A  |
    psrldq   xmm2, 8                      ; xmm2 = |  -     -  |  D  |  C  |
    pmovzxbw xmm2, xmm2                   ; xmm2 = |        D  |        C  | = |        B' |        A' |
    pmovzxbw xmm3, [rax + 4 * pixel_size] ; xmm3 = |        D' |        C' |
    
    ; Borro el word con la opacidad
    pand xmm1, xmm15
    pand xmm2, xmm15
    pand xmm3, xmm15

    ; Suma horizontal de las componentes
    movdqu xmm4, xmm2
    phaddw xmm4, xmm1 ; xmm4 = |  B  |  A  |  D  |  C  | = | (B.b + B.g) | (B.r + 0) | (A.b + A.g) | (A.r + 0) | ...
    movdqu xmm5, xmm3
    phaddw xmm5, xmm2 ; xmm5 = |  B' |  C' |  D' |  C' | = | (B'.b + B.g) | (B'.r + 0) | (A'.b + A.g) | (A'.r + 0) | ...

    ; finalmente tenemos la suma de todos los pixeles calculadas en 16bit.
    phaddw xmm5, xmm4 ; xmm5 = | B | A | D | C | B'| A'| D'| C'| = | (B.b + B.g + B.r) | (A.b + A.g + A.r) | ...

    ; Procedemos a insertar en la posicion de la opacidad de cada pixel, su respectiva suma
    movdqu   xmm4, xmm5 ; xmm4 = xmm5
    pmovzxwq xmm6, xmm5 ; xmm6 = |    sum D' |    sum C' |
    pslldq   xmm6, 6    ; xmm6 = | sum D'    | sum C'    | ; desplazo los valores a la posicion correspondiente a la op. del pixel
    paddw    xmm3, xmm6 ; coloco las sumas en C' y D'
    psrldq   xmm5, 4    ; xmm5 = |   -  |   -  | sum B | sum A | sum D | sum C | sum B'| sum C'| 
    pmovzxwq xmm6, xmm5 ; xmm6 = |    sum B' |    sum A' | = |    sum D  |    sum C  |
    pslldq   xmm6, 6    ; xmm6 = | sum B'    | sum A'    |
    paddw    xmm2, xmm6 ; coloco las sumas en C y D
    psrldq   xmm5, 8    ; xmm5 = | - | - | - | - | - | - | sum B | sum A |
    pmovzxwq xmm6, xmm5 ; xmm6 = |    sum B |    sum A |
    pslldq   xmm6, 6    ; xmm6 = | sum B    | sum A    |
    paddw    xmm1, xmm6 ; coloco las sumas en A y B


    ; xmm1 = |  B  |  A  |
    ; xmm2 = |  D  |  C  | = |  B' |  A' |
    ; xmm3 = |  D' |  C' |

    ; xmm10 guardo el max1 en la parte alta y el max2 en la baja
    ; xmm4  unpacked candidatos a max
    ; xmm0  resultado de la comparacion, hace de filtro para actualizar los max
    ; xmm5  cuentas aux

    ; Comparación de A y A' con los max de la fila anterior en xmm10
    movdqu     xmm4, xmm2    ; xmm4  = xmm2
    punpcklqdq xmm4, xmm1    ; xmm4  = |                      A |                      A'|

    call actualizarMax
    
    ; B y B':
    movdqu      xmm4, xmm2   ; xmm4  = xmm2
    punpckhqdq  xmm4, xmm1   ; xmm4  = |                      B |                      B'|
    
    call actualizarMax

    ; C y C':
    movdqu      xmm4, xmm3   ; xmm4 =  xmm3
    punpcklqdq  xmm4, xmm2   ; xmm4 =  |                      C |                      C'|
    
    call actualizarMax

    ; D y D':
    movdqu      xmm4, xmm3   ; xmm4 =  xmm3
    punpckhqdq  xmm4, xmm2   ; xmm4 =  |                      D |                      D'|

    call actualizarMax       ; xmm10 = |      max(Prev,A,B,C,D) | max(Prev',A',B',C',D') |
    ret


; Actualiza los max en xmm10 comparandolos con los candidatos en xmm4
actualizarMax:
    ; Comparación
    movdqu      xmm0, xmm4   ; xmm0  = xmm4
    pmaxuw      xmm0, xmm10  ; comparo con el max anterior en xmm10
    pcmpeqw     xmm0, xmm10  ; xmm0  = |0 / 1|  -  |  -  |  -  |0 / 1|  -  |  -  |  -  |
    pcmpeqq     xmm5, xmm5   ; xmm5  = 1
    pxor        xmm0, xmm5   ; invierto los valores

    ; Broadcast de la comparación
    movdqu      xmm5, xmm15  ; xmm5  = xmm15
    pandn       xmm5, xmm0   ; xmm5  = |1 / 0| 0000| 0000| 0000|1 / 0| 0000| 0000| 0000|
    movdqu      xmm0, xmm5   ; xmm0  = xmm5
    psrldq      xmm0, 2      ; xmm0  = | 0000|1 / 0| 0000| 0000| 0000|1 / 0| 0000| 0000|
    por         xmm0, xmm5   ; xmm0  = |1 / 0|1 / 0| 0000| 0000|1 / 0|1 / 0| 0000| 0000|
    movdqu      xmm5, xmm0   ; xmm5  = xmm0
    psrldq      xmm0, 4      ; xmm0  = | 0000| 0000|1 / 0|1 / 0| 0000| 0000|1 / 0|1 / 0|
    por         xmm0, xmm5   ; xmm0  = |                  1 / 0|                  1 / 0|

    ; Actualizo los maximos
    pblendvb   xmm10, xmm4
    ret
