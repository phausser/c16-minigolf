draw_course:
    lda #<course_segments
    sta COURSE_PTR
    lda #>course_segments
    sta COURSE_PTR + 1
    lda #COURSE_SEGMENT_COUNT
    sta SEGMENTS_LEFT
course_next:
    ldy #0
    lda (COURSE_PTR),y
    sta TEMP
    asl
    sta LINE_X
    lda #0
    rol
    sta LINE_X + 1
    iny
    lda (COURSE_PTR),y
    sta ROW_INDEX
    asl
    sta LINE_Y
    iny
    lda (COURSE_PTR),y
    cmp TEMP
    beq course_x_same
    bcc course_left
    sec
    sbc TEMP
    ldx #2
    bne course_x_ready
course_left:
    sta LINE_LEFT
    lda TEMP
    sec
    sbc LINE_LEFT
    ldx #$fe
    bne course_x_ready
course_x_same:
    lda #0
    ldx #0
course_x_ready:
    sta LINE_LEFT
    stx LINE_X_STEP
    iny
    lda (COURSE_PTR),y
    cmp ROW_INDEX
    beq course_y_same
    bcc course_up
    sec
    sbc ROW_INDEX
    ldx #2
    bne course_y_ready
course_up:
    sta LINE_LEFT
    lda ROW_INDEX
    sec
    sbc LINE_LEFT
    ldx #$fe
course_y_ready:
    sta LINE_LEFT
    stx LINE_Y_STEP
    jmp course_wall_offsets
course_y_same:
    lda #0
    sta LINE_Y_STEP
course_wall_offsets:
    iny
    lda (COURSE_PTR),y
    and #7
    tax
    lda wall_offsets_x,x
    sta WALL_X_OFFSET
    lda wall_offsets_y,x
    sta WALL_Y_OFFSET
course_line:
    jsr plot_wall
    lda LINE_LEFT
    beq course_advance
    dec LINE_LEFT
    clc
    lda LINE_X
    adc LINE_X_STEP
    sta LINE_X
    lda LINE_X_STEP
    bpl course_x_positive
    lda #$ff
    bne course_x_high
course_x_positive:
    lda #0
course_x_high:
    adc LINE_X + 1
    sta LINE_X + 1
    clc
    lda LINE_Y
    adc LINE_Y_STEP
    sta LINE_Y
    jmp course_line
course_advance:
    clc
    lda COURSE_PTR
    adc #5
    sta COURSE_PTR
    bcc course_pointer_ready
    inc COURSE_PTR + 1
course_pointer_ready:
    dec SEGMENTS_LEFT
    beq course_finished
    jmp course_next
course_finished:

    ; Cup ring is static and tests plotting at x > 255.
    lda #0
    sta POINT_INDEX
cup_next:
    ldx POINT_INDEX
    lda cup_dx,x
    clc
    adc #<CUP_X
    sta PIXEL_X
    lda cup_dx,x
    bpl cup_positive_x
    lda #$ff
    bne cup_x_sign
cup_positive_x:
    lda #0
cup_x_sign:
    adc #>CUP_X
    sta PIXEL_X + 1
    lda cup_dy,x
    clc
    adc #CUP_Y
    sta PIXEL_Y
    jsr plot_pixel
    inc POINT_INDEX
    lda POINT_INDEX
    cmp #CUP_POINTS
    bne cup_next
    rts

; A 3x3 stroke at each two-pixel segment step, offset into solid geometry.
; The contour remains the visible inner edge used by collisions.
plot_wall:
    lda #0
    sta ROW_INDEX
wall_row:
    lda LINE_Y
    clc
    adc WALL_Y_OFFSET
    sec
    sbc #1
    clc
    adc ROW_INDEX
    sta PIXEL_Y
    lda LINE_X
    clc
    adc WALL_X_OFFSET
    sta PIXEL_X
    lda WALL_X_OFFSET
    bpl wall_x_positive
    lda #$ff
    bne wall_x_high
wall_x_positive:
    lda #0
wall_x_high:
    adc LINE_X + 1
    sta PIXEL_X + 1
    lda PIXEL_X
    sec
    sbc #1
    sta PIXEL_X
    lda PIXEL_X + 1
    sbc #0
    sta PIXEL_X + 1
    lda #3
    sta GLYPH_BITS
wall_column:
    jsr plot_pixel
    inc PIXEL_X
    bne wall_no_carry
    inc PIXEL_X + 1
wall_no_carry:
    dec GLYPH_BITS
    bne wall_column
    inc ROW_INDEX
    lda ROW_INDEX
    cmp #3
    bne wall_row
    rts

