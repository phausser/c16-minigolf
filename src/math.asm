; All wide arithmetic is explicit. No decimal mode, ROM routines or floating
; point. Multiply is signed 16x16 -> signed 32; division is a positive
; fraction (numerator < denominator) -> floor(256*numerator/denominator).
!macro copy16 .source, .target {
    lda .source
    sta .target
    lda .source + 1
    sta .target + 1
}
!macro copy32 .source, .target {
    +copy16 .source, .target
    +copy16 .source + 2, .target + 2
}
!macro negate16 .value {
    sec
    lda #0
    sbc .value
    sta .value
    lda #0
    sbc .value + 1
    sta .value + 1
}
; Shared hot-scratch negations preserve X/Y and the macro's final flags.
; Keep other negations inline: their operands and call frequency differ.
negate_math_a:
    +negate16 M_A
    rts
negate_math_b:
    +negate16 M_B
    rts

!macro add16 .left, .right, .target {
    clc
    lda .left
    adc .right
    sta .target
    lda .left + 1
    adc .right + 1
    sta .target + 1
}
!macro sub16 .left, .right, .target {
    sec
    lda .left
    sbc .right
    sta .target
    lda .left + 1
    sbc .right + 1
    sta .target + 1
}

; Sum the two square products. QX/QY are unchanged.
square_q:
    +copy16 QX, M_A
    jsr square_small
    +copy32 M_PRODUCT, DX_WIDE
    +copy16 QY, M_A
    jsr square_small
    clc
    lda M_PRODUCT
    adc DX_WIDE
    sta M_PRODUCT
    lda M_PRODUCT + 1
    adc DX_WIDE + 1
    sta M_PRODUCT + 1
    lda M_PRODUCT + 2
    adc DX_WIDE + 2
    sta M_PRODUCT + 2
    lda M_PRODUCT + 3
    adc DX_WIDE + 3
    sta M_PRODUCT + 3
    rts

; Exact square for the bounded geometry/velocity inputs (|M_A| <= 2048).
; The 256-entry table gives lo^2; the cross term 2*lo*hi*256 is exact.
square_small:
    lda M_A + 1
    bpl square_absolute
    +negate16 M_A
square_absolute:
    ldx M_A
    lda square_lo,x
    sta M_PRODUCT
    lda square_hi,x
    sta M_PRODUCT + 1
    ldx M_A + 1
    lda square_lo,x
    sta M_PRODUCT + 2
    lda #0
    sta M_PRODUCT + 3
    txa
    beq square_finished
    ; Cross term 2*lo*hi*256: bit 8 of 2*lo adds hi to byte 2 once,
    ; the low byte of 2*lo is accumulated hi times in A.
    lda M_A
    asl
    sta M_MULTIPLICAND
    bcc square_cross_low
    txa
    clc
    adc M_PRODUCT + 2
    sta M_PRODUCT + 2
square_cross_low:
    lda M_PRODUCT + 1
square_cross:
    clc
    adc M_MULTIPLICAND
    bcc square_cross_next
    inc M_PRODUCT + 2
square_cross_next:
    dex
    bne square_cross
    sta M_PRODUCT + 1
square_finished:
    rts

; floor(M_A * uint8(M_B) / 256), |M_A| <= 2048. Whole-frame displacements
; are bounded by maximum strength, so a full 16x16 multiply is wasteful.
; The low byte product uses squares: l*B = (a^2 - (a-b)^2 + b^2) / 2 with
; a = max(l, B), b = min(l, B). Preserves Y and M_B.
multiply_fraction:
    lda M_A + 1
    sta M_SIGN
    bpl fraction_absolute
    +negate16 M_A
fraction_absolute:
    lda M_A
    ldx M_B
    cmp M_B
    bcs fraction_ordered      ; a = l (A), b = B (X)
    tax                       ; b = l
    lda M_B                   ; a = B
fraction_ordered:
    stx MUL_SMALL
    tax
    lda square_lo,x
    sta M_PRODUCT
    lda square_hi,x
    sta M_PRODUCT + 1
    txa
    sec
    sbc MUL_SMALL
    tax                       ; a - b
    sec
    lda M_PRODUCT
    sbc square_lo,x
    sta M_PRODUCT
    lda M_PRODUCT + 1
    sbc square_hi,x
    sta M_PRODUCT + 1
    ldx MUL_SMALL
    clc
    lda M_PRODUCT
    adc square_lo,x
    sta M_PRODUCT
    lda M_PRODUCT + 1
    adc square_hi,x
    ror                       ; 2ab has 17 bits: carry is bit 16
    ror M_PRODUCT
    ldx #0
    stx M_PRODUCT + 2
    ldx M_A + 1
    beq fraction_high_done
fraction_high_loop:
    clc
    adc M_B
    bcc fraction_high_no_carry
    inc M_PRODUCT + 2
fraction_high_no_carry:
    dex
    bne fraction_high_loop
fraction_high_done:
    sta M_PRODUCT + 1
fraction_sign:
    lda M_SIGN
    bpl fraction_return
    lda M_PRODUCT
    beq fraction_exact
    inc M_PRODUCT + 1
    bne fraction_exact
    inc M_PRODUCT + 2
fraction_exact:
    +negate16 M_PRODUCT + 1
fraction_return:
    rts

; Exact signed product when B is a Q1.8 unit component (|B| <= 256).
; Reuse the 8-bit fractional multiplier, including its low product byte.
multiply_unit:
    lda M_B + 1
    bpl unit_positive
    +negate16 M_A
    +negate16 M_B
unit_positive:
    lda M_B + 1
    beq unit_fraction
    +copy16 M_A, M_PRODUCT + 1
    lda #0
    sta M_PRODUCT
    jmp unit_extend
unit_fraction:
    jsr multiply_fraction
    lda M_SIGN
    bpl unit_extend
    sec
    lda #0
    sbc M_PRODUCT
    sta M_PRODUCT
unit_extend:
    lda M_PRODUCT + 2
    asl
    lda #0
    bcc unit_extended
    lda #$ff
unit_extended:
    sta M_PRODUCT + 3
    rts
