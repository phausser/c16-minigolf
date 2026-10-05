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
    ; Low multiplier byte: the running high byte stays in A.
    lda #0
    sta M_PRODUCT + 1
    sta M_PRODUCT + 3
    ldx #8
multiply_low_bit:
    lsr M_B
    bcc multiply_low_skip
    tay
    clc
    lda M_PRODUCT + 1
    adc M_A
    sta M_PRODUCT + 1
    tya
    adc M_A + 1
multiply_low_skip:
    ror
    ror M_PRODUCT + 1
    ror M_PRODUCT
    dex
    bne multiply_low_bit
    sta M_PRODUCT + 2
    ; High multiplier byte adds |A| << 8 per bit; small steps exit early.
    lda M_B + 1
    beq multiply_sign
    +copy16 M_A, M_MULTIPLICAND
    lda #0
    sta M_MULTIPLICAND + 2
multiply_high_bit:
    lsr M_B + 1
    bcc multiply_high_skip
    clc
    lda M_PRODUCT + 1
    adc M_MULTIPLICAND
    sta M_PRODUCT + 1
    lda M_PRODUCT + 2
    adc M_MULTIPLICAND + 1
    sta M_PRODUCT + 2
    lda M_PRODUCT + 3
    adc M_MULTIPLICAND + 2
    sta M_PRODUCT + 3
multiply_high_skip:
    lda M_B + 1
    beq multiply_sign
    asl M_MULTIPLICAND
    rol M_MULTIPLICAND + 1
    rol M_MULTIPLICAND + 2
    jmp multiply_high_bit
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

; Positive fraction: floor(256*remainder/denominator), remainder < denominator.
; The short path is exact for denominator < 32768; doubling cannot overflow.
; Wider inputs retain the 24-bit path (denominator <= 2^23).
divide_fraction:
    lda #0
    sta M_QUOT
    sta M_QUOT + 1
    ldx #8
    lda M_DEN + 2
    bne divide_bit
    lda M_DEN + 1
    bmi divide_bit
divide_short_bit:
    asl M_REM
    rol M_REM + 1
    asl M_QUOT
    sec
    lda M_REM
    sbc M_DEN
    tay
    lda M_REM + 1
    sbc M_DEN + 1
    bcc divide_short_next
    sta M_REM + 1
    sty M_REM
    inc M_QUOT
divide_short_next:
    dex
    bne divide_short_bit
    rts

divide_bit:
    asl M_REM
    rol M_REM + 1
    rol M_REM + 2
    asl M_QUOT
    ; Subtract speculatively; commit only when the full subtraction succeeds.
    sec
    lda M_REM
    sbc M_DEN
    tay
    lda M_REM + 1
    sbc M_DEN + 1
    sta M_TRIAL
    lda M_REM + 2
    sbc M_DEN + 2
    bcc divide_next
    sta M_REM + 2
    lda M_TRIAL
    sta M_REM + 1
    sty M_REM
    inc M_QUOT
divide_next:
    dex
    bne divide_bit
    rts
