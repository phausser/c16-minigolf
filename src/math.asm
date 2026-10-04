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

!macro root_shift {
    asl M_PRODUCT
    rol M_PRODUCT + 1
    rol M_PRODUCT + 2
    rol M_PRODUCT + 3
    rol M_REM
    rol M_REM + 1
}
; Exact restoring root for bounded speed squares: input < 2^22.
; The 11-bit root keeps remainder and trial within 16 bits.
sqrt_speed:
    ldx #10
sqrt_speed_shift:
    asl M_PRODUCT
    rol M_PRODUCT + 1
    rol M_PRODUCT + 2
    rol M_PRODUCT + 3
    dex
    bne sqrt_speed_shift
    lda #0
    sta M_QUOT
    sta M_QUOT + 1
    sta M_REM
    sta M_REM + 1
    lda #11
    sta M_COUNT
sqrt_pair:
    +root_shift
    +root_shift
    +copy16 M_QUOT, M_TRIAL
    asl M_TRIAL
    rol M_TRIAL + 1
    asl M_TRIAL
    rol M_TRIAL + 1
    inc M_TRIAL
    asl M_QUOT
    rol M_QUOT + 1
    lda M_REM + 1
    cmp M_TRIAL + 1
    bcc sqrt_next
    bne sqrt_subtract
    lda M_REM
    cmp M_TRIAL
    bcc sqrt_next
sqrt_subtract:
    +sub16 M_REM, M_TRIAL, M_REM
    inc M_QUOT
sqrt_next:
    dec M_COUNT
    bne sqrt_pair
    rts

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
; A 128-entry quarter table replaces a multiply: low-byte values >=128
; use (u+128)^2 = u^2 + 256*u + 16384. High-byte cross terms are exact.
square_small:
    lda M_A + 1
    bpl square_absolute
    +negate16 M_A
square_absolute:
    lda M_A
    and #127
    tax
    lda small_square_lo,x
    sta M_PRODUCT
    lda small_square_hi,x
    sta M_PRODUCT + 1
    lda M_A
    bpl square_low_ready
    txa
    clc
    adc #64
    adc M_PRODUCT + 1
    sta M_PRODUCT + 1
square_low_ready:
    ldx M_A + 1
    lda small_square_lo,x
    sta M_PRODUCT + 2
    lda #0
    sta M_PRODUCT + 3
    lda M_A
    asl
    sta M_MULTIPLICAND
    lda #0
    rol
    sta M_MULTIPLICAND + 1
    cpx #0
    beq square_finished
square_cross:
    clc
    lda M_PRODUCT + 1
    adc M_MULTIPLICAND
    sta M_PRODUCT + 1
    lda M_PRODUCT + 2
    adc M_MULTIPLICAND + 1
    sta M_PRODUCT + 2
    dex
    bne square_cross
square_finished:
    rts

; floor(M_A * uint8(M_B) / 256), |M_A| <= 2048. Whole-frame displacements
; are bounded by maximum strength, so a full 16x16 multiply is wasteful.
multiply_fraction:
    lda M_A + 1
    sta M_SIGN
    bpl fraction_absolute
    +negate16 M_A
fraction_absolute:
    lda #0
    sta M_PRODUCT
    sta M_PRODUCT + 1
    sta M_PRODUCT + 2
    lda M_B
    sta M_COUNT
    lda M_A
    beq fraction_high_part
fraction_eight_bits:
    ldx #8
fraction_multiply_bit:
    lsr M_B
    bcc fraction_no_add
    clc
    lda M_PRODUCT + 1
    adc M_A
    sta M_PRODUCT + 1
fraction_no_add:
    ror M_PRODUCT + 1
    ror M_PRODUCT
    dex
    bne fraction_multiply_bit
fraction_high_part:
    ldx M_A + 1
    beq fraction_sign
fraction_high_loop:
    clc
    lda M_PRODUCT + 1
    adc M_COUNT
    sta M_PRODUCT + 1
    bcc fraction_high_no_carry
    inc M_PRODUCT + 2
fraction_high_no_carry:
    dex
    bne fraction_high_loop
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
