; Exact radial 45-degree entry shortcut; all other paths use the general sweep.
circle_diagonal_guard:
    lda RADIUS_SQUARED + 2
    cmp #4
    bne diagonal_guard_no
    lda QX + 1
    bpl diagonal_guard_no
    lda STEP_X + 1
    bmi diagonal_guard_no
    lda QX
    cmp QY
    bne diagonal_guard_no
    lda QX + 1
    cmp QY + 1
    bne diagonal_guard_no
    lda STEP_X
    cmp STEP_Y
    bne diagonal_guard_no
    lda STEP_X + 1
    cmp STEP_Y + 1
    bne diagonal_guard_no
    sec
    rts
diagonal_guard_no:
    clc
    rts
