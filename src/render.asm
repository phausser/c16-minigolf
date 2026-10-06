draw_dynamic:
    jsr ball_screen_position
    lda HOLED
    beq ball_visible
    rts
ball_visible:
    sec
    lda BALL_SCREEN_X
    sbc #2
    sta PIXEL_X
    lda BALL_SCREEN_X + 1
    sbc #0
    sta PIXEL_X + 1
    lda BALL_SCREEN_Y
    sec
    sbc #2
    sta PIXEL_Y
    ; Five mask rows per pixel alignment; the right byte column is touched
    ; only from alignment 4 and only left of x = 312.
    lda PIXEL_X
    and #7
    sta TEMP
    asl
    asl
    adc TEMP
    sta BALL_MASK_INDEX       ; alignment * 5
    lda #0
    sta BALL_SIDE
ball_column:
    lda BALL_MASK_INDEX
    sta BALL_MASK_POS
    clc
    adc #5
    sta BALL_MASK_END
    lda PIXEL_Y
    and #7
    sta BALL_ROW_Y
    lda PIXEL_Y
    lsr
    lsr
    lsr
    sta BALL_CELL_ROW
    ; One dynamic character per cell, then the rows inside it. Cells off
    ; the playfield are drawn into the idle renderer scratch instead.
ball_cell:
    lda BALL_CELL_ROW
    beq ball_cell_hidden
    cmp #21
    bcs ball_cell_hidden
    jsr dynamic_cell
    jmp ball_cell_ready
ball_cell_hidden:
    lda #<SCRATCH_BASE
    sta FONT_PTR
    lda #>SCRATCH_BASE
    sta FONT_PTR + 1
ball_cell_ready:
    ldx BALL_MASK_POS
    ldy BALL_ROW_Y
ball_row:
    lda (FONT_PTR),y
    and ball_masks,x
    sta (FONT_PTR),y
    inx
    cpx BALL_MASK_END
    beq ball_column_done
    iny
    cpy #8
    bne ball_row
    stx BALL_MASK_POS
    inc BALL_CELL_ROW
    lda #0
    sta BALL_ROW_Y
    beq ball_cell
ball_column_done:
    lda BALL_SIDE
    bne ball_columns_done
    lda TEMP
    cmp #4
    bcc ball_columns_done
    lda PIXEL_X + 1
    beq ball_right_column
    lda PIXEL_X
    cmp #<(312 - 256)
    bcs ball_columns_done
ball_right_column:
    inc BALL_SIDE
    lda BALL_MASK_INDEX
    clc                       ; carry differs between the x < 256 and x >= 256 paths
    adc #40                   ; the right table
    sta BALL_MASK_INDEX
    clc
    lda PIXEL_X
    adc #8
    sta PIXEL_X
    bcc ball_column
    inc PIXEL_X + 1
    bne ball_column
ball_columns_done:
    lda PAUSED
    ora ROLLING
    beq aim_draw
    rts
aim_draw:

    ; Fractional accumulation gives visibly distinct 128 directions without
    ; a separate bitmap for each angle. This is display data, not physics.
    lda ANGLE
    jsr lookup_aim_step
    sta AIM_STEP_X
    lda ANGLE
    sec
    sbc #32
    jsr lookup_aim_step
    sta AIM_STEP_Y
    lda BALL_SCREEN_X
    sta AIM_X
    lda BALL_SCREEN_X + 1
    sta AIM_X + 1
    lda BALL_SCREEN_Y
    sta AIM_Y
    lda #0
    sta AIM_Y + 1
    ldx #4
aim_start_shift:
    asl AIM_X
    rol AIM_X + 1
    asl AIM_Y
    rol AIM_Y + 1
    dex
    bne aim_start_shift
    ; Walking dots: start AIM_PHASE single pixels (a quarter step each)
    ; further out, so every dot moves outwards and the outermost one
    ; reappears at the inner end of the fixed 8..35 pixel window.
    lda AIM_STEP_X
    pha
    lda AIM_STEP_Y
    pha
    ldx #1
aim_quarter:
    lda AIM_STEP_X,x
    cmp #$80
    ror
    cmp #$80
    ror
    sta AIM_STEP_X,x
    dex
    bpl aim_quarter
    lda AIM_PHASE
    and #3
    tax
    beq aim_phase_done
aim_phase:
    jsr advance_aim
    dex
    bne aim_phase
aim_phase_done:
    pla
    sta AIM_STEP_Y
    pla
    sta AIM_STEP_X
    stx POINT_INDEX
aim_next:
    jsr advance_aim
    ; Skip the first point inside/next to the ball.
    inc POINT_INDEX
    lda POINT_INDEX
    cmp #2
    bcc aim_next
    jsr aim_coordinates
    lda PIXEL_X + 1
    cmp #1
    bcc aim_x_on_screen
    bne aim_skip_pixel
    lda PIXEL_X
    cmp #64
    bcs aim_skip_pixel
aim_x_on_screen:
    lda PIXEL_X
    and #7
    tax
    lda pixel_masks,x
    sta PIXEL_MASK            ; one pixel; the ball leaves a multi-bit mask
    jsr punch_pixel           ; clips y to the playfield itself
aim_skip_pixel:
    lda POINT_INDEX
    cmp #8
    bne aim_next
aim_done:
    rts

; Four pixels along ANGLE in 1/16 pixel units: (cos + 2) / 4, signed.
lookup_aim_step:
    jsr cosine_unit
    clc
    lda M_A
    adc #2
    sta M_A
    lda M_A + 1
    adc #0
    ldx #2
aim_unit_scale:
    cmp #$80
    ror
    ror M_A
    dex
    bne aim_unit_scale
    lda M_A
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

; Whole status row: "BAHN n" left, "PUNKTE n" right aligned.
draw_status:
    lda #0
    sta TEXT_COLUMN
    lda #<hud_hole
    ldx #>hud_hole
    jsr draw_text_at
    inc TEXT_COLUMN
    ldx HOLE
    inx
    txa
    jsr draw_number
    lda #8                    ; "BAHN nn PAR n", the power bar from column 15
    sta TEXT_COLUMN
    lda #<hud_par_word
    ldx #>hud_par_word
    jsr draw_text_at
    inc TEXT_COLUMN
    ldx HOLE
    lda course_par,x
    jsr draw_number
    ; "PUNKTE n" ends in column 39: one digit gets a leading blank.
    lda #31
    sta TEXT_COLUMN
    lda SHOTS
    cmp #10
    lda #<hud_shots
    bcc status_shots
    lda #<(hud_shots + 1)
status_shots:
    ldx #>hud_shots
    jsr draw_text_at
    lda SHOTS
    jsr number_digits
    cpx #'0'
    beq number_single_digit
    bne number_pair
; Round summary: total par left ("PAR nn "), "SUMME nnn" right.
draw_summary:
    lda #0
    sta TEXT_COLUMN
    lda #<hud_par_text
    ldx #>hud_par_text
    jsr draw_text_at
    lda #31
    sta TEXT_COLUMN
    lda #<hud_total
    ldx #>hud_total
    jsr draw_text_at
    lda TOTAL
    ldy #'0'
total_hundreds:
    cmp #100
    bcc total_tens
    sbc #100
    iny
    bne total_hundreds
total_tens:
    pha
    tya
    cmp #'0'
    bne total_digit
    lda #' '
total_digit:
    jsr draw_glyph
    inc TEXT_COLUMN
    pla
    jsr number_digits         ; a round has at least 18 strokes
    jmp number_pair

; A = 0..99, left aligned in two cells from TEXT_COLUMN.
draw_number:
    jsr number_digits
    cpx #'0'
    beq number_single
number_pair:
    sta TEMP
    txa
    jsr draw_glyph
    inc TEXT_COLUMN
    lda TEMP
    jmp draw_glyph
number_single:
    jsr draw_glyph
    inc TEXT_COLUMN
    lda #' '
number_single_digit:
    jmp draw_glyph
; A = 0..99 -> X = tens digit, A = units digit (ASCII).
number_digits:
    ldx #'0'
number_tens:
    cmp #10
    bcc number_units
    sbc #10
    inx
    bne number_tens
number_units:
    ora #'0'
    rts

; Ten-cell bar centred in row 24. Each cell is one of nine glyphs:
; row 3 is always a full line, rows 1, 2, 4 and 5 grow from the left
; by 5 * POWER / 2 pixels (80 at full power).
draw_power:
    lda #24
    jsr class_row_pointer
    lda COURSE_PTR + 1
    clc
    adc #>(SCREEN_BASE - ATTR_BASE)
    sta COURSE_PTR + 1
    lda POWER
    lsr
    sta TEMP
    lda POWER
    asl
    adc TEMP                  ; POWER <= 32: carry clear
    sta TEMP
    ldy #BAR_COLUMN
power_bar_cell:
    lda TEMP
    cmp #8
    bcc power_bar_width
    lda #8
power_bar_width:
    clc
    adc #BAR_CHAR
    sta (COURSE_PTR),y
    lda TEMP
    sec
    sbc #8
    bcs power_bar_next
    lda #0
power_bar_next:
    sta TEMP
    iny
    cpy #BAR_COLUMN + BAR_CELLS
    bne power_bar_cell
    rts

draw_text_at:
    sta TEXT_PTR
    stx TEXT_PTR + 1
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

; A = ASCII 32..93. The screen code selects the ROM glyph copied at startup.
draw_glyph:
    cmp #64
    bcc glyph_code
    and #63
glyph_code:
    pha
    lda TEXT_ROW
    jsr class_row_pointer
    lda COURSE_PTR + 1
    clc
    adc #>(SCREEN_BASE - ATTR_BASE)
    sta COURSE_PTR + 1
    pla
    ldy TEXT_COLUMN
    sta (COURSE_PTR),y
    rts

wall_offsets_x:
!byte $ff,$ff,0,1,1,1,0,$ff
wall_offsets_y:
!byte 0,$ff,$ff,$ff,0,1,1,1
hud_hole:
!text "BAHN",0
hud_shots:
!text " PUNKTE ",0
hud_par_word:
!text "PAR",0
hud_total:
!text "SUMME ",0
BAR_COLUMN = 15
BAR_CELLS = 10
bar_masks:
!byte $00,$80,$c0,$e0,$f0,$f8,$fc,$fe,$ff

; Inverted ball rows (the pixels to keep) for alignments 0..7: left byte
; column, then the right one. Row 1 leaves the highlight pixel set.
!macro ball_mask_row .shape, .shift, .right {
!if .right { !byte ((.shape << (8 - .shift)) & $ff) XOR $ff } else { !byte (.shape >> .shift) XOR $ff }
}
!macro ball_mask_rows .shift, .right {
    +ball_mask_row $70, .shift, .right
    +ball_mask_row $b8, .shift, .right
    +ball_mask_row $f8, .shift, .right
    +ball_mask_row $f8, .shift, .right
    +ball_mask_row $70, .shift, .right
}
ball_masks:
!for ball_shift, 0, 7 { +ball_mask_rows ball_shift, 0 }
!for ball_shift, 0, 7 { +ball_mask_rows ball_shift, 1 }

; The cup is a round 7-pixel hole: a dark rim with the shadow of its edge
; inside at the top left; the lit far wall at the bottom right stays floor.
; Plotting covers x > 255 too.
draw_cup:
    lda #6
    sta POINT_INDEX           ; hole row 0..6, dy = row - 3
cup_row:
    lda POINT_INDEX
    clc
    adc COURSE_CUP_Y
    sec
    sbc #3
    sta PIXEL_Y
    ldx POINT_INDEX
    lda cup_rows,x
    asl                       ; bits 6..0 are dx = -3..3
    sta GLYPH
    sec
    lda COURSE_CUP_X
    sbc #3
    sta PIXEL_X
    lda COURSE_CUP_X_HI
    sbc #0
    sta PIXEL_X + 1
cup_pixel:
    asl GLYPH
    bcc cup_pixel_next
    jsr plot_pixel
cup_pixel_next:
    inc PIXEL_X
    bne cup_pixel_more
    inc PIXEL_X + 1
cup_pixel_more:
    lda GLYPH
    bne cup_pixel
    dec POINT_INDEX
    bpl cup_row
    rts

cup_rows:
!byte %00011100
!byte %00111110
!byte %01111111
!byte %01111001
!byte %01110001
!byte %00110010
!byte %00011100
