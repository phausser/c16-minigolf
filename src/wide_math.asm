; Immutable wide arithmetic in black bitmap row 23.
multiply_signed:
    lda M_A + 1
    eor M_B + 1
    sta M_SIGN
    lda M_A + 1
    bpl multiply_a_positive
    +negate16 M_A
multiply_a_positive:
    lda M_B + 1
    bpl multiply_b_positive
    +negate16 M_B
multiply_b_positive:
    +copy16 M_A, M_MULTIPLICAND
    lda #0
    sta M_MULTIPLICAND + 2
    sta M_MULTIPLICAND + 3
    sta M_PRODUCT
    sta M_PRODUCT + 1
    sta M_PRODUCT + 2
    sta M_PRODUCT + 3
multiply_bit:
    lsr M_B + 1
    ror M_B
    bcc multiply_skip
    clc
    lda M_PRODUCT
    adc M_MULTIPLICAND
    sta M_PRODUCT
    lda M_PRODUCT + 1
    adc M_MULTIPLICAND + 1
    sta M_PRODUCT + 1
    lda M_PRODUCT + 2
    adc M_MULTIPLICAND + 2
    sta M_PRODUCT + 2
    lda M_PRODUCT + 3
    adc M_MULTIPLICAND + 3
    sta M_PRODUCT + 3
multiply_skip:
    lda M_B
    ora M_B + 1
    beq multiply_sign
    asl M_MULTIPLICAND
    rol M_MULTIPLICAND + 1
    rol M_MULTIPLICAND + 2
    rol M_MULTIPLICAND + 3
    jmp multiply_bit
multiply_sign:
    lda M_SIGN
    bpl multiply_done
    sec
    lda #0
    sbc M_PRODUCT
    sta M_PRODUCT
    lda #0
    sbc M_PRODUCT + 1
    sta M_PRODUCT + 1
    lda #0
    sbc M_PRODUCT + 2
    sta M_PRODUCT + 2
    lda #0
    sbc M_PRODUCT + 3
    sta M_PRODUCT + 3
multiply_done:
    rts

divide_fraction:
    lda #0
    sta M_QUOT
    sta M_QUOT + 1
    ldx #8
divide_bit:
    asl M_REM
    rol M_REM + 1
    rol M_REM + 2
    asl M_QUOT
    lda M_REM + 2
    cmp M_DEN + 2
    bcc divide_next
    bne divide_subtract
    lda M_REM + 1
    cmp M_DEN + 1
    bcc divide_next
    bne divide_subtract
    lda M_REM
    cmp M_DEN
    bcc divide_next
divide_subtract:
    sec
    lda M_REM
    sbc M_DEN
    sta M_REM
    lda M_REM + 1
    sbc M_DEN + 1
    sta M_REM + 1
    lda M_REM + 2
    sbc M_DEN + 2
    sta M_REM + 2
    inc M_QUOT
divide_next:
    dex
    bne divide_bit
    rts

