draw_course:
    lda #<course_segments
    sta COURSE_PTR
    lda #>course_segments
    sta COURSE_PTR + 1
    lda #COURSE_SEGMENT_COUNT
    sta SEGMENTS_LEFT
course_next:
    ldy #0
    lda (COURSE_PTR),y        ; x/2, including coordinates above 255
    asl
    sta LINE_X
    lda #0
    rol
    sta LINE_X + 1
    iny
    lda (COURSE_PTR),y
    asl
    sta LINE_Y
    iny
    lda (COURSE_PTR),y
    tax
    lda line_steps_x,x
    sta LINE_X_STEP
    lda line_steps_y,x
    sta LINE_Y_STEP
    iny
    lda (COURSE_PTR),y
    sta LINE_LEFT
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
    adc #4
    sta COURSE_PTR
    bcc course_pointer_ready
    inc COURSE_PTR + 1
course_pointer_ready:
    dec SEGMENTS_LEFT
    bne course_next

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

; A 3x3 stroke at each two-pixel segment step. For this hardware preview
; wall strokes are centered; final collision contours will define inner edges.
plot_wall:
    lda #0
    sta ROW_INDEX
wall_row:
    lda LINE_Y
    sec
    sbc #1
    clc
    adc ROW_INDEX
    sta PIXEL_Y
    lda LINE_X
    sec
    sbc #1
    sta PIXEL_X
    lda LINE_X + 1
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

draw_dynamic:
    lda #0
    sta POINT_INDEX
ball_next:
    ldx POINT_INDEX
    lda ball_dx,x
    clc
    adc #<BALL_X
    sta PIXEL_X
    lda #>BALL_X
    sta PIXEL_X + 1          ; fixed test start does not cross a page
    lda ball_dy,x
    clc
    adc #BALL_Y
    sta PIXEL_Y
    jsr plot_dynamic
    inc POINT_INDEX
    lda POINT_INDEX
    cmp #BALL_POINTS
    bne ball_next
    lda PAUSED
    bne aim_done

    ; Fractional accumulation gives visibly distinct 128 directions without
    ; a separate bitmap for each angle. This is display data, not physics.
    ldx ANGLE
    lda aim_steps_x,x
    sta AIM_STEP_X
    lda aim_steps_y,x
    sta AIM_STEP_Y
    lda #<(BALL_X * 16)
    sta AIM_X
    lda #>(BALL_X * 16)
    sta AIM_X + 1
    lda #<(BALL_Y * 16)
    sta AIM_Y
    lda #>(BALL_Y * 16)
    sta AIM_Y + 1
    lda #0
    sta POINT_INDEX
aim_next:
    jsr advance_aim
    ; Skip the first two points inside/next to the ball.
    inc POINT_INDEX
    lda POINT_INDEX
    cmp #3
    bcc aim_next
    jsr aim_coordinates
    jsr plot_dynamic
    lda POINT_INDEX
    cmp #10
    bne aim_next
aim_done:
    rts

advance_aim:
    clc
    lda AIM_X
    adc AIM_STEP_X
    sta AIM_X
    lda #0
    bit AIM_STEP_X
    bpl aim_x_sign
    lda #$ff
aim_x_sign:
    adc AIM_X + 1
    sta AIM_X + 1
    clc
    lda AIM_Y
    adc AIM_STEP_Y
    sta AIM_Y
    lda #0
    bit AIM_STEP_Y
    bpl aim_y_sign
    lda #$ff
aim_y_sign:
    adc AIM_Y + 1
    sta AIM_Y + 1
    rts

aim_coordinates:
    lda AIM_X
    sta PIXEL_X
    lda AIM_X + 1
    sta PIXEL_X + 1
    ldx #4
aim_shift_x:
    lsr PIXEL_X + 1
    ror PIXEL_X
    dex
    bne aim_shift_x
    lda AIM_Y
    sta PIXEL_Y
    lda AIM_Y + 1
    ldx #4
aim_shift_y:
    lsr
    ror PIXEL_Y
    dex
    bne aim_shift_y
    rts

draw_static_hud:
    lda #22
    sta TEXT_ROW
    lda #1
    sta TEXT_COLUMN
    lda #<hud_title
    sta TEXT_PTR
    lda #>hud_title
    sta TEXT_PTR + 1
    jsr draw_text
    inc TEXT_ROW
    lda #1
    sta TEXT_COLUMN
    lda #<hud_controls
    sta TEXT_PTR
    lda #>hud_controls
    sta TEXT_PTR + 1
    jsr draw_text
    inc TEXT_ROW
    lda #1
    sta TEXT_COLUMN
    lda #<hud_power
    sta TEXT_PTR
    lda #>hud_power
    sta TEXT_PTR + 1
    jmp draw_text

draw_power:
    lda #24
    sta TEXT_ROW
    lda #7
    sta TEXT_COLUMN
    ldx #0
    lda POWER
power_tens:
    cmp #10
    bcc power_digits
    sec
    sbc #10
    inx
    bne power_tens
power_digits:
    clc
    adc #'0'
    sta TEMP
    txa
    clc
    adc #'0'
    jsr draw_glyph
    inc TEXT_COLUMN
    lda TEMP
    jsr draw_glyph

    lda POWER
    clc
    adc #1
    lsr
    sta BAR_LEFT
    lda #15
    sta TEXT_COLUMN
power_bar:
    lda #' '
    ldx BAR_LEFT
    beq power_empty
    dec BAR_LEFT
    lda #'#'
power_empty:
    jsr draw_glyph
    inc TEXT_COLUMN
    lda TEXT_COLUMN
    cmp #31
    bne power_bar
    lda #33
    sta TEXT_COLUMN
    lda #<hud_ready
    ldx #>hud_ready
    ldy PAUSED
    beq power_status
    lda #<hud_paused
    ldx #>hud_paused
power_status:
    sta TEXT_PTR
    stx TEXT_PTR + 1
    jmp draw_text

draw_text:
    ldy #0
    lda (TEXT_PTR),y
    beq text_done
    jsr draw_glyph
    inc TEXT_COLUMN
    inc TEXT_PTR
    bne draw_text
    inc TEXT_PTR + 1
    jmp draw_text
text_done:
    rts

; A = ASCII 32..93; aligned bitmap glyphs overwrite only their own cell.
draw_glyph:
    sec
    sbc #32
    sta FONT_PTR
    lda #0
    sta FONT_PTR + 1
    ldx #3
glyph_offset:
    asl FONT_PTR
    rol FONT_PTR + 1
    dex
    bne glyph_offset
    clc
    lda FONT_PTR
    adc #<font
    sta FONT_PTR
    lda FONT_PTR + 1
    adc #>font
    sta FONT_PTR + 1
    ldx TEXT_ROW
    lda bitmap_rows_lo,x
    sta BITMAP_PTR
    lda bitmap_rows_hi,x
    sta BITMAP_PTR + 1
    lda TEXT_COLUMN
    ldx #0
    asl
    asl
    asl
    bcc glyph_column
    inx
glyph_column:
    clc
    adc BITMAP_PTR
    sta BITMAP_PTR
    txa
    adc BITMAP_PTR + 1
    sta BITMAP_PTR + 1
    ldy #0
glyph_copy:
    lda (FONT_PTR),y
    sta (BITMAP_PTR),y
    iny
    cpy #8
    bne glyph_copy
    rts

line_steps_x:
!byte 2,2,0,$fe,$fe,$fe,0,2
line_steps_y:
!byte 0,2,2,2,0,$fe,$fe,$fe
hud_title:
!text "C16 MINIGOLF / 16 KB / ZIELTEST",0
hud_controls:
!text "A/D RICHTUNG  W/S KRAFT  P PAUSE",0
hud_power:
!text "KRAFT 16/32  [                ]",0
hud_ready:
!text "BEREIT",0
hud_paused:
!text "PAUSE ",0
