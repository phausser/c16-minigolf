normalize_component:
    lda M_A + 1
    sta M_SIGN
    bpl normalize_positive
    +negate16 M_A
normalize_positive:
    +copy16 M_A, M_REM
    +copy16 SPEED, M_DEN
    lda #0
    sta M_REM + 2
    sta M_DEN + 2
    lda M_REM
    cmp M_DEN
    bne normalize_fraction
    lda M_REM + 1
    cmp M_DEN + 1
    bne normalize_fraction
    lda #0
    sta M_QUOT
    lda #1
    sta M_QUOT + 1
    bne normalize_sign
normalize_fraction:
    jsr divide_fraction
normalize_sign:
    lda M_SIGN
    bpl normalize_return
    +negate16 M_QUOT
normalize_return:
    rts
